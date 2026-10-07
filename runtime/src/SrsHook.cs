using System;
using System.IO;
using System.Reflection;
using System.Threading;

// Loaded only for the SRS process explicitly started by this launcher.
// No SRS binaries, bindings, profiles or server settings are rewritten.
internal class StartupHook
{
    public static void Initialize()
    {
        EFSRSLink.Session session;
        try { session = EFSRSLink.Session.FromEnvironment(); }
        catch { return; }
        // Prevent SRS child processes from inheriting this process-local hook.
        Environment.SetEnvironmentVariable("DOTNET_STARTUP_HOOKS", null);
        Environment.SetEnvironmentVariable("EFSRS11L_SESSION", null);
        Environment.SetEnvironmentVariable("EFSRS11L_TOKEN", null);
        Environment.SetEnvironmentVariable("EFSRS11L_RADIO1", null);
        Environment.SetEnvironmentVariable("EFSRS11L_RADIO2", null);
        var worker = new Thread(delegate() { new EFSRSSrsHook.Runner(session).Run(); });
        worker.IsBackground = true;
        worker.Name = "EF-SRS ENC and HOLD";
        worker.Start();
    }
}

namespace EFSRSSrsHook
{
    internal sealed class SrsAccess : EFSRSLink.IEncryptionPort
    {
        private readonly FieldInfo _instance, _selected, _enc, _key, _encMode;
        private readonly PropertyInfo _radioInfo, _eam, _sending, _isSending, _sendingOn;
        private readonly MethodInfo _current, _getRadio, _setKey, _toggle;
        public SrsAccess(Assembly srs)
        {
            if (srs.GetName().Name != "SR-ClientRadio" || srs.GetName().Version != new Version(2,4,1,0))
                throw new InvalidOperationException("Only SRS 2.4.1.0 is supported.");
            const string prefix = "Ciribob.DCS.SimpleRadio.Standalone.Client.";
            Type client = NeedType(srs, prefix + "Singletons.ClientStateSingleton");
            Type helper = NeedType(srs, prefix + "Utils.RadioHelper");
            _instance = client.GetField("_instance", BindingFlags.Static | BindingFlags.NonPublic);
            _radioInfo = client.GetProperty("DcsPlayerRadioInfo");
            _eam = client.GetProperty("ExternalAWACSModeConnected");
            _sending = client.GetProperty("RadioSendingState");
            if (_instance == null || _radioInfo == null || _eam == null || _sending == null)
                throw new InvalidOperationException("Unknown SRS client-state structure.");
            _selected = _radioInfo.PropertyType.GetField("selected");
            _current = _radioInfo.PropertyType.GetMethod("IsCurrent", Type.EmptyTypes);
            _isSending = _sending.PropertyType.GetProperty("IsSending");
            _sendingOn = _sending.PropertyType.GetProperty("SendingOn");
            _getRadio = helper.GetMethod("GetRadio", new Type[] { typeof(int) });
            _setKey = helper.GetMethod("SetEncryptionKey", new Type[] { typeof(int), typeof(int) });
            _toggle = helper.GetMethod("ToggleEncryption", new Type[] { typeof(int) });
            if (_selected == null || _current == null || _isSending == null || _sendingOn == null || _getRadio == null || _setKey == null || _toggle == null
                || !_getRadio.IsStatic || !_setKey.IsStatic || !_toggle.IsStatic)
                throw new InvalidOperationException("Unknown SRS radio interface.");
            _enc = _getRadio.ReturnType.GetField("enc");
            _key = _getRadio.ReturnType.GetField("encKey");
            _encMode = _getRadio.ReturnType.GetField("encMode");
            if (_enc == null || _enc.FieldType != typeof(bool) || _key == null || _key.FieldType != typeof(byte) || _encMode == null || !_encMode.FieldType.IsEnum)
                throw new InvalidOperationException("Unknown SRS encryption structure.");
        }
        private static Type NeedType(Assembly assembly, string name)
        { return assembly.GetType(name, true); }
        public bool Initialized { get { return _instance.GetValue(null) != null; } }
        public EFSRSLink.Snapshot Capture()
        {
            // Called on the existing WPF dispatcher. Do not construct the SRS
            // singleton from a worker thread or change the user's selection.
            object client = _instance.GetValue(null);
            var state = new EFSRSLink.Snapshot { Stamp = DateTime.UtcNow.Ticks, Selected = -1, SendingOn = -1 };
            if (client == null) return state;
            object info = _radioInfo.GetValue(client, null);
            state.Current = (bool)_eam.GetValue(client, null) && info != null && (bool)_current.Invoke(info, null);
            if (!state.Current) return state;
            state.Selected = Convert.ToInt32(_selected.GetValue(info), EFSRSLink.Wire.Invariant);
            object sending = _sending.GetValue(client, null);
            if (sending != null)
            {
                state.Sending = (bool)_isSending.GetValue(sending, null);
                state.SendingOn = Convert.ToInt32(_sendingOn.GetValue(sending, null), EFSRSLink.Wire.Invariant);
            }
            return state;
        }
        public EFSRSLink.EncryptionState Read(int radio)
        {
            object value = _getRadio.Invoke(null, new object[] { radio });
            if (value == null) return new EFSRSLink.EncryptionState();
            return new EFSRSLink.EncryptionState { Available = true, Enabled = (bool)_enc.GetValue(value),
                Key = Convert.ToInt32(_key.GetValue(value), EFSRSLink.Wire.Invariant), Mode = Convert.ToInt32(_encMode.GetValue(value), EFSRSLink.Wire.Invariant) };
        }
        public void SetKey(int radio, int key) { _setKey.Invoke(null, new object[] { radio, key }); }
        public void Toggle(int radio) { _toggle.Invoke(null, new object[] { radio }); }
    }

    internal sealed class Runner
    {
        private readonly EFSRSLink.Session _session;
        private SrsAccess _access;
        private bool _ready;
        private readonly long[] _ack = new long[2];
        private readonly int[] _result = new int[2];
        private string _lastError;
        public Runner(EFSRSLink.Session session) { _session = session; }
        private static Assembly Find(string name)
        {
            foreach (Assembly value in AppDomain.CurrentDomain.GetAssemblies())
                if (value.GetName().Name == name) return value;
            return null;
        }
        public void Run()
        {
            DateTime deadline = DateTime.UtcNow.AddSeconds(40);
            while (true)
            {
                if (File.Exists(_session.FilePath("stop.txt"))) return;
                try
                {
                    Assembly srs = Find("SR-ClientRadio"), wpf = Find("PresentationFramework");
                    if (srs != null && wpf != null)
                    {
                        Type application = wpf.GetType("System.Windows.Application", true);
                        object app = application.GetProperty("Current").GetValue(null, null);
                        if (app != null)
                        {
                            object dispatcher = application.GetProperty("Dispatcher").GetValue(app, null);
                            Type dt = dispatcher.GetType();
                            if ((bool)dt.GetProperty("HasShutdownStarted").GetValue(dispatcher,null)) return;
                            MethodInfo invoke = dt.GetMethod("Invoke", new Type[] { typeof(Action) });
                            if (invoke == null) throw new InvalidOperationException("WPF dispatcher interface not supported.");
                            invoke.Invoke(dispatcher, new object[] { (Action)delegate() { Tick(srs); } });
                        }
                    }
                }
                catch (Exception ex)
                {
                    Exception cause = ex;
                    while (cause.InnerException != null) cause = cause.InnerException;
                    if (!_ready)
                    {
                        EFSRSLink.Wire.Write(_session.FilePath("hook.error"), cause.GetType().Name + ": " + cause.Message);
                        return;
                    }
                    if (_lastError != cause.Message) { Log("ERROR " + cause.Message); _lastError = cause.Message; }
                    // Do not publish a healthy snapshot on a failed read. The
                    // bridge rejects old snapshots after two seconds.
                }
                if (!_ready && DateTime.UtcNow > deadline)
                {
                    EFSRSLink.Wire.Write(_session.FilePath("hook.error"), "SRS interface did not initialize within 40 seconds.");
                    return;
                }
                Thread.Sleep(100);
            }
        }
        private void Tick(Assembly srs)
        {
            if (_access == null) _access = new SrsAccess(srs);
            if (!_access.Initialized) return;
            if (!_ready)
            {
                EFSRSLink.Wire.Write(_session.FilePath("hook.ready"), _session.Token);
                _ready = true;
                Log("SRS 2.4.1.0 interface ready. Waiting for EAM.");
            }
            EFSRSLink.Snapshot state = _access.Capture();
            Process(0, _session.Radio1, state.Current);
            Process(1, _session.Radio2, state.Current);
            state.Ack1 = _ack[0]; state.Result1 = _result[0];
            state.Ack2 = _ack[1]; state.Result2 = _result[1];
            EFSRSLink.Wire.Write(_session.FilePath("status.txt"), state.Encode(_session.Token));
            _lastError = null;
        }
        private void Process(int slot, int radio, bool current)
        {
            string text = EFSRSLink.Wire.ReadSmall(_session.CommandPath(slot + 1));
            if (text == null) return;
            EFSRSLink.EncryptionRequest request = EFSRSLink.EncryptionRequest.Parse(text, _session.Token, radio);
            if (request == null || request.Sequence <= _ack[slot]) return;
            int result;
            if (!EFSRSLink.Wire.Fresh(request.Stamp, DateTime.UtcNow.Ticks, 5)) result = 3;
            else if (!current) return; // Briefly wait for EAM, never replay a stale command.
            else result = EFSRSLink.EncryptionControl.Apply(_access, request);
            _ack[slot] = request.Sequence; _result[slot] = result;
            EFSRSLink.EncryptionState actual = current ? _access.Read(radio) : new EFSRSLink.EncryptionState();
            Log("Radio " + radio + " ENC request=" + request.Enabled + " KEY=" + request.Key + " result=" + result
                + " readback=" + actual.Enabled + "/" + actual.Key + " mode=" + actual.Mode);
        }
        private void Log(string text)
        {
            try { File.AppendAllText(_session.FilePath("hook.log"), DateTime.UtcNow.ToString("o") + " " + text + Environment.NewLine); }
            catch { }
        }
    }
}
