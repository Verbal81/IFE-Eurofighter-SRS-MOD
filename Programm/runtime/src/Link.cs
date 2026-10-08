using System;
using System.IO;
using System.Text;
using System.Globalization;

namespace EFSRSLink
{
    // Deliberately uses only mscorlib APIs so the same code can run in the
    // Windows PowerShell bridge and through the SRS .NET runtime's facade.
    public static class Wire
    {
        public const string Protocol = "EFSRS11L";
        public static readonly CultureInfo Invariant = CultureInfo.InvariantCulture;
        public static string Number(long value) { return value.ToString(Invariant); }
        public static long Integer(string value) { return long.Parse(value, NumberStyles.Integer, Invariant); }
        public static bool Fresh(long stamp, long now, int seconds)
        { return stamp <= now + TimeSpan.TicksPerSecond && stamp >= now - seconds * TimeSpan.TicksPerSecond; }
        public static string ReadSmall(string path)
        {
            if (!File.Exists(path)) return null;
            using (var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            {
                if (stream.Length > 4096) return null;
                using (var reader = new StreamReader(stream, Encoding.UTF8)) return reader.ReadToEnd().Trim();
            }
        }
        public static void Write(string path, string text)
        {
            string temp = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            string backup = temp + ".bak";
            try
            {
                File.WriteAllText(temp, text + "\n", new UTF8Encoding(false));
                if (File.Exists(path)) File.Replace(temp, path, backup);
                else File.Move(temp, path);
            }
            finally
            {
                if (File.Exists(temp)) File.Delete(temp);
                if (File.Exists(backup)) File.Delete(backup);
            }
        }
    }

    public sealed class Session
    {
        public readonly string Directory, Token;
        public readonly int Radio1, Radio2;
        public Session(string directory, string token, int r1, int r2)
        {
            if (token == null || token.Length != 32) throw new InvalidOperationException("Missing EF-SRS session token.");
            for (int i = 0; i < token.Length; i++)
                if ("0123456789abcdef".IndexOf(token[i]) < 0) throw new InvalidOperationException("Invalid EF-SRS token.");
            if (r1 < 1 || r1 > 10 || r2 < 1 || r2 > 10 || r1 == r2) throw new InvalidOperationException("Invalid radio mapping.");
            Directory = directory; Token = token; Radio1 = r1; Radio2 = r2;
        }
        public static Session FromEnvironment()
        {
            string token = Environment.GetEnvironmentVariable("EFSRS11L_TOKEN");
            string directory = Environment.GetEnvironmentVariable("EFSRS11L_SESSION");
            string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "EF-SRS", "runtime-v11m4-finalrc2");
            string expected = Path.Combine(root, "session-" + token);
            if (String.IsNullOrEmpty(directory) || !Path.GetFullPath(directory).Equals(Path.GetFullPath(expected), StringComparison.OrdinalIgnoreCase)
                || !System.IO.Directory.Exists(directory)) throw new InvalidOperationException("Invalid EF-SRS session directory.");
            return new Session(directory, token, int.Parse(Environment.GetEnvironmentVariable("EFSRS11L_RADIO1"), Wire.Invariant),
                int.Parse(Environment.GetEnvironmentVariable("EFSRS11L_RADIO2"), Wire.Invariant));
        }
        public string FilePath(string name) { return Path.Combine(Directory, name); }
        public string CommandPath(int slot) { return FilePath("enc-" + slot + ".txt"); }
    }

    public sealed class EncryptionRequest
    {
        public long Sequence, Stamp;
        public int Radio, Key;
        public bool Enabled;
        public string Encode(string token)
        {
            return String.Join("|", new string[] { Wire.Protocol, token, Wire.Number(Sequence), Wire.Number(Stamp),
                Wire.Number(Radio), Enabled ? "1" : "0", Wire.Number(Key) });
        }
        public static EncryptionRequest Parse(string text, string token, int expectedRadio)
        {
            try
            {
                string[] p = text.Split('|');
                if (p.Length != 7 || p[0] != Wire.Protocol || p[1] != token || (p[5] != "0" && p[5] != "1")) return null;
                var r = new EncryptionRequest { Sequence = Wire.Integer(p[2]), Stamp = Wire.Integer(p[3]),
                    Radio = checked((int)Wire.Integer(p[4])), Enabled = p[5] == "1", Key = checked((int)Wire.Integer(p[6])) };
                if (r.Sequence < 1 || r.Radio != expectedRadio || r.Radio < 1 || r.Radio > 10 || r.Key < 1 || r.Key > 252) return null;
                return r;
            }
            catch { return null; }
        }
    }

    public struct EncryptionState { public bool Available, Enabled; public int Mode, Key; }
    public interface IEncryptionPort
    {
        EncryptionState Read(int radio);
        void SetKey(int radio, int key);
        void Toggle(int radio);
    }
    public static class EncryptionControl
    {
        // 1 confirmed, 2 radio/server does not permit overlay encryption,
        // 3 expired request, 4 failed read-back. Never substitutes Retransmit.
        public static int Apply(IEncryptionPort port, EncryptionRequest request)
        {
            if (request == null || request.Radio < 1 || request.Radio > 10 || request.Key < 1 || request.Key > 252) return 4;
            EncryptionState state = port.Read(request.Radio);
            if (!state.Available || state.Mode != 1) return 2;
            if (state.Key != request.Key) port.SetKey(request.Radio, request.Key);
            state = port.Read(request.Radio);
            if (!state.Available || state.Mode != 1 || state.Key != request.Key) return 4;
            if (state.Enabled != request.Enabled) port.Toggle(request.Radio);
            state = port.Read(request.Radio);
            return state.Available && state.Mode == 1 && state.Key == request.Key && state.Enabled == request.Enabled ? 1 : 4;
        }
    }

    public sealed class Snapshot
    {
        public long Stamp, Ack1, Ack2;
        public bool Current, Sending;
        public int Selected, SendingOn, Result1, Result2;
        public string Encode(string token)
        {
            return String.Join("|", new string[] { Wire.Protocol, token, Wire.Number(Stamp), Current ? "1" : "0",
                Wire.Number(Selected), Sending ? "1" : "0", Wire.Number(SendingOn), Wire.Number(Ack1),
                Wire.Number(Result1), Wire.Number(Ack2), Wire.Number(Result2) });
        }
        public static Snapshot Parse(string text, string token, long now)
        {
            try
            {
                string[] p = text.Split('|');
                if (p.Length != 11 || p[0] != Wire.Protocol || p[1] != token || (p[3] != "0" && p[3] != "1") || (p[5] != "0" && p[5] != "1")) return null;
                var s = new Snapshot { Stamp = Wire.Integer(p[2]), Current = p[3] == "1", Selected = checked((int)Wire.Integer(p[4])),
                    Sending = p[5] == "1", SendingOn = checked((int)Wire.Integer(p[6])), Ack1 = Wire.Integer(p[7]),
                    Result1 = checked((int)Wire.Integer(p[8])), Ack2 = Wire.Integer(p[9]), Result2 = checked((int)Wire.Integer(p[10])) };
                if (!Wire.Fresh(s.Stamp, now, 2) || s.Selected < -1 || s.Selected > 10 || s.SendingOn < -1 || s.SendingOn > 10
                    || s.Ack1 < 0 || s.Ack2 < 0 || s.Result1 < 0 || s.Result1 > 4 || s.Result2 < 0 || s.Result2 > 4) return null;
                return s;
            }
            catch { return null; }
        }
        public int CockpitRadio(int r1, int r2)
        {
            if (!Current) return 0;
            // HOLD is the active-radio label, not a PTT lamp. SRS joystick
            // radio bindings and its UI both update RadioInfo.selected.
            int id = Selected;
            return id == r1 ? 1 : id == r2 ? 2 : 0;
        }
    }

    public sealed class FeedbackGate
    {
        public int LastApplied = -1;
        private int _expected;
        private long _commandTime;
        public void CockpitCommand(int active, long now) { _expected = active; _commandTime = now; LastApplied = active; }
        public int Propose(Snapshot state, int r1, int r2, long now)
        {
            if (state == null || !Wire.Fresh(state.Stamp, now, 2)) return 0;
            int active = state.CockpitRadio(r1, r2);
            if (active == 0) return 0;
            if (_expected != 0)
            {
                if (active != _expected && now - _commandTime < TimeSpan.TicksPerMillisecond * 600) return 0;
                _expected = 0;
            }
            return active == LastApplied ? 0 : active;
        }
    }

    public static class SelfTest
    {
        private sealed class FakeRadio : IEncryptionPort
        {
            public EncryptionState State = new EncryptionState { Available = true, Mode = 1, Key = 1 };
            public int Toggles, Keys;
            public bool RejectKey;
            public EncryptionState Read(int radio) { return State; }
            public void SetKey(int radio, int key) { Keys++; if (!RejectKey) State.Key = key; }
            public void Toggle(int radio) { Toggles++; State.Enabled = !State.Enabled; }
        }
        private static void Check(bool ok, string name) { if (!ok) throw new Exception("EF-SRS self-test: " + name); }
        public static string Run()
        {
            string token = "0123456789abcdef0123456789abcdef";
            long now = DateTime.UtcNow.Ticks;
            var request = new EncryptionRequest { Sequence = 1, Stamp = now, Radio = 1, Key = 20, Enabled = true };
            Check(EncryptionRequest.Parse(request.Encode(token), token, 1).Key == 20, "request round trip");
            Check(EncryptionRequest.Parse(request.Encode(token), new string('a',32), 1) == null, "foreign session");
            Check(EncryptionRequest.Parse(request.Encode(token), token, 2) == null, "wrong radio");
            var radio = new FakeRadio();
            Check(EncryptionControl.Apply(radio, request) == 1 && radio.State.Enabled && radio.State.Key == 20, "ENC ON and key");
            Check(EncryptionControl.Apply(radio, request) == 1 && radio.Toggles == 1 && radio.Keys == 1, "idempotent retry");
            request.Enabled = false;
            Check(EncryptionControl.Apply(radio, request) == 1 && !radio.State.Enabled, "ENC OFF");
            radio.State.Mode = 0; int count = radio.Toggles;
            Check(EncryptionControl.Apply(radio, request) == 2 && radio.Toggles == count, "server restriction");
            radio.State.Mode = 1; request.Key = 0;
            Check(EncryptionControl.Apply(radio, request) == 4, "key 0 rejected");
            request.Key = 253; Check(EncryptionControl.Apply(radio, request) == 4, "key 253 rejected");
            request.Key = 252; Check(EncryptionControl.Apply(radio, request) == 1 && radio.State.Key == 252, "key 252");
            request.Key = 1; Check(EncryptionControl.Apply(radio, request) == 1 && radio.State.Key == 1, "key 1");
            radio.RejectKey = true; request.Key = 22; request.Enabled = true; count = radio.Toggles;
            Check(EncryptionControl.Apply(radio, request) == 4 && radio.Toggles == count, "failed key does not toggle ENC");
            var status = new Snapshot { Stamp = now, Current = true, Selected = 2, Sending = true, SendingOn = 2 };
            Check(Snapshot.Parse(status.Encode(token),token,now).CockpitRadio(1,2) == 2, "joystick selects UHF2");
            status.Selected = 1; Check(status.CockpitRadio(1,2) == 1, "SRS UI selects UHF1 even while sending state lags");
            status.Selected = 0; Check(status.CockpitRadio(1,2) == 0, "intercom does not invent UHF");
            Check(Snapshot.Parse(status.Encode(token), token, now + 3 * TimeSpan.TicksPerSecond) == null, "stale status rejected");
            Check(Snapshot.Parse(status.Encode(token), new string('b',32), now) == null, "foreign status rejected");
            var gate = new FeedbackGate(); gate.CockpitCommand(2,now); status.Selected = 1;
            Check(gate.Propose(status,1,2,now) == 0, "old frame cannot reverse ACT");
            status.Selected = 2; Check(gate.Propose(status,1,2,now) == 0, "ACT acknowledgement");
            status.Selected = 1; Check(gate.Propose(status,1,2,now) == 1, "next joystick change follows");
            gate.LastApplied = 1; Check(gate.Propose(status,1,2,now) == 0, "no feedback echo");
            return "21 ENC/protocol/HOLD checks passed";
        }
    }
}
