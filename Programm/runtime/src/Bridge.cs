using System;
using System.Windows.Forms;
using System.IO;
using System.Collections.Generic;
using System.Globalization;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Runtime.InteropServices;
using Microsoft.FlightSimulator.SimConnect;


namespace EFSRSBridge
{
    public static class Entry
    {
        [STAThread]
        public static void Run()
        {
            bool createdNew;
            using (var single = new System.Threading.Mutex(true, @"Local\EF_SRS_Bridge_v1_SingleInstance", out createdNew))
            {
                if (!createdNew) return;
                Logger.Initialize();
                Logger.Info("EF-SRS Bridge v1.1m4 ENC/HOLD starting.");
                Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
                Application.ThreadException += (s, e) => Logger.Error("Unhandled UI thread exception", e.Exception);
                AppDomain.CurrentDomain.UnhandledException += (s, e) => Logger.Error("Unhandled AppDomain exception", e.ExceptionObject as Exception);
                try
                {
                    Application.EnableVisualStyles();
                    Application.SetCompatibleTextRenderingDefault(false);
                    string configDir = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "EF-SRS");
                    System.IO.Directory.CreateDirectory(configDir);
                    var config = BridgeConfig.Load(System.IO.Path.Combine(configDir, "EFSRSBridge.ini"));
                    var session = EFSRSLink.Session.FromEnvironment();
                    string readyPath = session.FilePath("bridge.ready");
                    using (var context = new BridgeApplicationContext(config))
                    {
                        EFSRSLink.Wire.Write(readyPath, session.Token);
                        Logger.Info("Bridge runtime ready; waiting for MSFS SimConnect.");
                        Application.Run(context);
                    }
                }
                catch (Exception ex) { Logger.Error("Fatal startup error", ex); throw; }
            }
        }
    }
}

namespace EFSRSBridge
{
    internal static class Logger
    {
        private static readonly object Sync = new object();
        private static string _path;
        public static void Initialize()
        {
            string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "EF-SRS");
            Directory.CreateDirectory(dir);
            _path = Path.Combine(dir, "bridge.log");
            try { if (File.Exists(_path) && new FileInfo(_path).Length > 5*1024*1024) { if (File.Exists(_path+".old")) File.Delete(_path+".old"); File.Move(_path,_path+".old"); } } catch { }
        }
        public static void Info(string m) { Write("INFO",m); }
        public static void Warn(string m) { Write("WARN",m); }
        public static void Error(string m, Exception ex=null) { Write("ERROR", ex==null?m:m+" | "+ex); }
        private static void Write(string level,string m) { if (String.IsNullOrEmpty(_path)) return; lock(Sync) { try { File.AppendAllText(_path, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff")+" ["+level+"] "+m+Environment.NewLine); } catch {} } }
    }
}


namespace EFSRSBridge
{
    internal sealed class MessageWindow : NativeWindow, IDisposable
    {
        public const int WM_USER_SIMCONNECT = 0x0402;
        public event Action SimConnectMessage;
        public MessageWindow()
        {
            var cp = new CreateParams { Caption = "EF-SRS Bridge v0.6 Message Window" };
            CreateHandle(cp);
        }
        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WM_USER_SIMCONNECT)
            {
                try { if (SimConnectMessage != null) SimConnectMessage(); }
                catch (Exception ex) { Logger.Error("Unhandled SimConnect message error", ex); }
            }
            base.WndProc(ref m);
        }
        public void Dispose() { DestroyHandle(); }
    }
}


namespace EFSRSBridge
{
    internal sealed class BridgeApplicationContext : ApplicationContext, IDisposable
    {
        private readonly MessageWindow _messageWindow;
        private readonly SimConnectBridge _bridge;
        private readonly Timer _reconnectTimer;
        private readonly Timer _feedbackTimer;
        private bool _disposed;
        public BridgeApplicationContext(BridgeConfig config)
        {
            _messageWindow = new MessageWindow();
            _bridge = new SimConnectBridge(_messageWindow.Handle, config);
            _messageWindow.SimConnectMessage += _bridge.ReceiveMessage;
            _reconnectTimer = new Timer { Interval = 5000 };
            _reconnectTimer.Tick += (_, __) => _bridge.EnsureConnected();
            _reconnectTimer.Start();
            _feedbackTimer = new Timer { Interval = 100 };
            _feedbackTimer.Tick += (_, __) => _bridge.PollSrsFeedback();
            _feedbackTimer.Start();
            _bridge.EnsureConnected();
            Application.ApplicationExit += (_, __) => Dispose();
        }
        public new void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            _feedbackTimer.Stop();
            _feedbackTimer.Dispose();
            _reconnectTimer.Stop();
            _reconnectTimer.Dispose();
            _bridge.Dispose();
            _messageWindow.Dispose();
            Logger.Info("EF-SRS Bridge v0.6 stopped.");
            base.Dispose();
        }
    }
}


namespace EFSRSBridge
{
    internal sealed class BridgeConfig
    {
        public string SrsHost { get; private set; }
        public int SrsPort { get; private set; }
        public int Radio1Id { get; private set; }
        public int Radio2Id { get; private set; }
        public bool SyncBothOnModeOn { get; private set; }

        public BridgeConfig()
        {
            SrsHost = "127.0.0.1";
            SrsPort = 9040;
            Radio1Id = 1;
            Radio2Id = 2;
            SyncBothOnModeOn = true;
        }

        public static BridgeConfig Load(string path)
        {
            var cfg = new BridgeConfig();
            if (!File.Exists(path))
            {
                File.WriteAllText(path,
                    "# EF-SRS Bridge v0.6 configuration\r\n" +
                    "SrsHost=127.0.0.1\r\n" +
                    "SrsPort=9040\r\n" +
                    "Radio1Id=1\r\n" +
                    "Radio2Id=2\r\n" +
                    "SyncBothOnModeOn=true\r\n");
                return cfg;
            }

            var values = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (string rawLine in File.ReadAllLines(path))
            {
                string line = rawLine.Trim();
                if (line.Length == 0 || line.StartsWith("#") || line.StartsWith(";")) continue;
                int equals = line.IndexOf('=');
                if (equals <= 0) continue;
                values[line.Substring(0, equals).Trim()] = line.Substring(equals + 1).Trim();
            }

            string host, port, r1, r2, sync;
            int p, id1, id2;
            bool syncValue;
            if (values.TryGetValue("SrsHost", out host) && !string.IsNullOrWhiteSpace(host)) cfg.SrsHost = host;
            if (values.TryGetValue("SrsPort", out port) && int.TryParse(port, out p)) cfg.SrsPort = p;
            if (values.TryGetValue("Radio1Id", out r1) && int.TryParse(r1, out id1)) cfg.Radio1Id = id1;
            if (values.TryGetValue("Radio2Id", out r2) && int.TryParse(r2, out id2)) cfg.Radio2Id = id2;
            if (values.TryGetValue("SyncBothOnModeOn", out sync) && bool.TryParse(sync, out syncValue)) cfg.SyncBothOnModeOn = syncValue;
            return cfg;
        }
    }
}


namespace EFSRSBridge
{
    internal sealed class SrsClient : IDisposable
    {
        private const int CommandActiveRadio = 1;
        private const int CommandSetVolume = 5;
        private const int CommandFrequencySet = 12;
        private const int CommandIntercomChannel = 20;

        private readonly UdpClient _udp = new UdpClient();
        private readonly IPEndPoint _endpoint;

        public SrsClient(string host, int port)
        {
            IPAddress address;
            if (!IPAddress.TryParse(host, out address)) address = Dns.GetHostAddresses(host)[0];
            _endpoint = new IPEndPoint(address, port);
        }

        public void SetFrequency(int radioId, double frequencyMHz)
        {
            string json = "{\"RadioId\":" + radioId.ToString(CultureInfo.InvariantCulture) +
                          ",\"Frequency\":" + frequencyMHz.ToString("0.000000", CultureInfo.InvariantCulture) +
                          ",\"Command\":" + CommandFrequencySet.ToString(CultureInfo.InvariantCulture) + "}";
            Send(json);
        }

        public void SelectRadio(int radioId)
        {
            string json = "{\"RadioId\":" + radioId.ToString(CultureInfo.InvariantCulture) +
                          ",\"Command\":" + CommandActiveRadio.ToString(CultureInfo.InvariantCulture) + "}";
            Send(json);
        }

        public void SetVolume(int radioId, double volume01)
        {
            if (volume01 < 0.0) volume01 = 0.0;
            if (volume01 > 1.0) volume01 = 1.0;
            string json = "{\"RadioId\":" + radioId.ToString(CultureInfo.InvariantCulture) +
                          ",\"Volume\":" + volume01.ToString("0.000", CultureInfo.InvariantCulture) +
                          ",\"Command\":" + CommandSetVolume.ToString(CultureInfo.InvariantCulture) + "}";
            Send(json);
        }

        public void SetIntercomChannel(int channel)
        {
            string json = "{\"RadioId\":" + channel.ToString(CultureInfo.InvariantCulture) +
                          ",\"Command\":" + CommandIntercomChannel.ToString(CultureInfo.InvariantCulture) + "}";
            Send(json);
        }

        private void Send(string json)
        {
            byte[] bytes = Encoding.UTF8.GetBytes(json);
            _udp.Send(bytes, bytes.Length, _endpoint);
        }

        public void Dispose() { _udp.Dispose(); }
    }
}


namespace EFSRSBridge
{
    internal sealed class SimConnectBridge : IDisposable
    {
        private readonly IntPtr _windowHandle;
        private readonly BridgeConfig _config;
        private readonly SrsClient _srs;
        private SimConnect _sim;
        private bool _disposed;
        private bool _definitionRegistered;
        private bool _stateInitialized;
        private double _lastCommitSeq;
        private double _lastVolumeSeq;
        private double _lastIntercomSeq;
        private double _lastActiveSeq;
        private double _lastEncryptionSeq;
        private int _lastActiveRadio = -1;
        private bool _lastMode;

        private enum Definitions { SrsCockpitData = 1, ActiveRadioFeedback = 2 }
        private readonly EFSRSLink.Session _session;
        private EFSRSLink.FeedbackGate _feedback = new EFSRSLink.FeedbackGate();
        private long _encryptionRequest;
        private readonly long[] _acknowledged = new long[2];
        private readonly long[] _issued = new long[2];
        private bool _feedbackErrorLogged;
        private int _pendingFeedback;

        [StructLayout(LayoutKind.Sequential, Pack = 1)]
        private struct ActiveRadioFeedback { public double ActiveRadio; }
        private enum Requests { SrsCockpitData = 1 }

        [StructLayout(LayoutKind.Sequential, Pack = 1)]
        private struct SrsCockpitData
        {
            public double Mode;
            public double SelectedRadio;
            public double ActiveRadio;
            public double ActiveSequence;
            public double Radio1FrequencyMHz;
            public double Radio2FrequencyMHz;
            public double CommitSequence;
            public double Radio1VolumePct;
            public double Radio2VolumePct;
            public double IntercomVolumePct;
            public double IntercomChannel;
            public double VolumeSequence;
            public double IntercomSequence;
            public double Radio1Encryption;
            public double Radio2Encryption;
            public double Radio1EncryptionKey;
            public double Radio2EncryptionKey;
            public double EncryptionSequence;
        }

        public SimConnectBridge(IntPtr windowHandle, BridgeConfig config)
        {
            _windowHandle = windowHandle;
            _config = config;
            _session = EFSRSLink.Session.FromEnvironment();
            if (config.Radio1Id != _session.Radio1 || config.Radio2Id != _session.Radio2)
                throw new InvalidOperationException("Bridge radio mapping changed after launcher validation.");
            _srs = new SrsClient(config.SrsHost, config.SrsPort);
        }

        public void EnsureConnected()
        {
            if (_disposed || _sim != null) return;
            try
            {
                Logger.Info("Creating SimConnect client...");
                _sim = new SimConnect("EF-SRS Bridge v1.1b", _windowHandle, MessageWindow.WM_USER_SIMCONNECT, null, 0);
                _sim.OnRecvOpen += OnRecvOpen;
                _sim.OnRecvQuit += OnRecvQuit;
                _sim.OnRecvException += OnRecvException;
                _sim.OnRecvSimobjectData += OnRecvSimobjectData;
                Logger.Info("SimConnect connection requested.");
            }
            catch (COMException ex)
            {
                Logger.Warn("MSFS/SimConnect not available yet: " + ex.Message);
                Disconnect();
            }
            catch (Exception ex)
            {
                Logger.Error("SimConnect connection failed", ex);
                Disconnect();
            }
        }

        public void ReceiveMessage()
        {
            if (_sim == null) return;
            try { _sim.ReceiveMessage(); }
            catch (Exception ex) { Logger.Error("SimConnect ReceiveMessage error", ex); Disconnect(); }
        }

        private void OnRecvOpen(SimConnect sender, SIMCONNECT_RECV_OPEN data)
        {
            Logger.Info("Connected to Microsoft Flight Simulator via SimConnect.");
            RegisterDefinitionsAndRequest();
        }

        private void RegisterDefinitionsAndRequest()
        {
            if (_sim == null || _definitionRegistered) return;
            _sim.AddToDataDefinition(Definitions.SrsCockpitData, "L:EFSRS_Mode", "number", SIMCONNECT_DATATYPE.FLOAT64, 0.0f, SimConnect.SIMCONNECT_UNUSED);
            _sim.AddToDataDefinition(Definitions.SrsCockpitData, "L:EFSRS_SelectedRadio", "number", SIMCONNECT_DATATYPE.FLOAT64, 0.0f, SimConnect.SIMCONNECT_UNUSED);
            _sim.AddToDataDefinition(Definitions.SrsCockpitData, "L:EFSRS_ActiveRadio", "number", SIMCONNECT_DATATYPE.FLOAT64, 0.0f, SimConnect.SIMCONNECT_UNUSED);
            _sim.AddToDataDefinition(Definitions.SrsCockpitData, "L:EFSRS_ActiveSeq", "number", SIMCONNECT_DATATYPE.FLOAT64, 0.0f, SimConnect.SIMCONNECT_UNUSED);
            _sim.AddToDataDefinition(Definitions.SrsCockpitData, "L:EFSRS_Radio1Freq", "number", SIMCONNECT_DATATYPE.FLOAT64, 0.0001f, SimConnect.SIMCONNECT_UNUSED);
            _sim.AddToDataDefinition(Definitions.SrsCockpitData, "L:EFSRS_Radio2Freq", "number", SIMCONNECT_DATATYPE.FLOAT64, 0.0001f, SimConnect.SIMCONNECT_UNUSED);
            _sim.AddToDataDefinition(Definitions.SrsCockpitData, "L:EFSRS_CommitSeq", "number", SIMCONNECT_DATATYPE.FLOAT64, 0.0f, SimConnect.SIMCONNECT_UNUSED);
            _sim.AddToDataDefinition(Definitions.SrsCockpitData, "L:EFSRS_Radio1Vol", "number", SIMCONNECT_DATATYPE.FLOAT64, 0.0f, SimConnect.SIMCONNECT_UNUSED);
            _sim.AddToDataDefinition(Definitions.SrsCockpitData, "L:EFSRS_Radio2Vol", "number", SIMCONNECT_DATATYPE.FLOAT64, 0.0f, SimConnect.SIMCONNECT_UNUSED);
            _sim.AddToDataDefinition(Definitions.SrsCockpitData, "L:EFSRS_IntercomVol", "number", SIMCONNECT_DATATYPE.FLOAT64, 0.0f, SimConnect.SIMCONNECT_UNUSED);
            _sim.AddToDataDefinition(Definitions.SrsCockpitData, "L:EFSRS_IntercomChannel", "number", SIMCONNECT_DATATYPE.FLOAT64, 0.0f, SimConnect.SIMCONNECT_UNUSED);
            _sim.AddToDataDefinition(Definitions.SrsCockpitData, "L:EFSRS_VolumeSeq", "number", SIMCONNECT_DATATYPE.FLOAT64, 0.0f, SimConnect.SIMCONNECT_UNUSED);
            _sim.AddToDataDefinition(Definitions.SrsCockpitData, "L:EFSRS_IntercomSeq", "number", SIMCONNECT_DATATYPE.FLOAT64, 0.0f, SimConnect.SIMCONNECT_UNUSED);
            _sim.AddToDataDefinition(Definitions.SrsCockpitData, "L:EFSRS_Radio1Enc", "number", SIMCONNECT_DATATYPE.FLOAT64, 0.0f, SimConnect.SIMCONNECT_UNUSED);
            _sim.AddToDataDefinition(Definitions.SrsCockpitData, "L:EFSRS_Radio2Enc", "number", SIMCONNECT_DATATYPE.FLOAT64, 0.0f, SimConnect.SIMCONNECT_UNUSED);
            _sim.AddToDataDefinition(Definitions.SrsCockpitData, "L:EFSRS_Radio1EncKey", "number", SIMCONNECT_DATATYPE.FLOAT64, 0.0f, SimConnect.SIMCONNECT_UNUSED);
            _sim.AddToDataDefinition(Definitions.SrsCockpitData, "L:EFSRS_Radio2EncKey", "number", SIMCONNECT_DATATYPE.FLOAT64, 0.0f, SimConnect.SIMCONNECT_UNUSED);
            _sim.AddToDataDefinition(Definitions.SrsCockpitData, "L:EFSRS_EncryptionSeq", "number", SIMCONNECT_DATATYPE.FLOAT64, 0.0f, SimConnect.SIMCONNECT_UNUSED);
            _sim.RegisterDataDefineStruct<SrsCockpitData>(Definitions.SrsCockpitData);
            _sim.RequestDataOnSimObject(Requests.SrsCockpitData, Definitions.SrsCockpitData,
                SimConnect.SIMCONNECT_OBJECT_ID_USER, SIMCONNECT_PERIOD.SIM_FRAME,
                SIMCONNECT_DATA_REQUEST_FLAG.CHANGED, 0, 0, 0);
            _sim.AddToDataDefinition(Definitions.ActiveRadioFeedback, "L:EFSRS_ActiveRadio", "number", SIMCONNECT_DATATYPE.FLOAT64, 0.0f, SimConnect.SIMCONNECT_UNUSED);
            _sim.RegisterDataDefineStruct<ActiveRadioFeedback>(Definitions.ActiveRadioFeedback);
            _definitionRegistered = true;
            Logger.Info("v0.7.1 cockpit LVars registered (ACT + Encryption). Native COM1/COM2 remain separate from SRS.");
        }

        private void OnRecvSimobjectData(SimConnect sender, SIMCONNECT_RECV_SIMOBJECT_DATA data)
        {
            if ((Requests)data.dwRequestID != Requests.SrsCockpitData || data.dwData == null || data.dwData.Length == 0) return;
            var state = (SrsCockpitData)data.dwData[0];
            bool mode = state.Mode >= 0.5;
            int selected = (int)Math.Round(state.SelectedRadio);
            int active = (int)Math.Round(state.ActiveRadio);
            if (_pendingFeedback == active)
            {
                Logger.Info("HOLD read-back confirmed: UHF" + active);
                _pendingFeedback = 0;
            }

            if (!_stateInitialized)
            {
                _stateInitialized = true;
                _lastCommitSeq = state.CommitSequence;
                _lastVolumeSeq = state.VolumeSequence;
                _lastIntercomSeq = state.IntercomSequence;
                _lastActiveSeq = state.ActiveSequence;
                _lastEncryptionSeq = state.EncryptionSequence;
                _lastActiveRadio = active;
                _feedback.LastApplied = active;
                _lastMode = mode;
                Logger.Info(String.Format(CultureInfo.InvariantCulture, "Initial: SRS={0}; Page={1}; ActiveUHF={2}; UHF1={3:0.000}; UHF2={4:0.000}; INTCH={5:0}; VOL={6:0}/{7:0}/{8:0}", mode ? "ON" : "OFF", selected, active, state.Radio1FrequencyMHz, state.Radio2FrequencyMHz, state.IntercomChannel, state.Radio1VolumePct, state.Radio2VolumePct, state.IntercomVolumePct));
                if (mode) ActivateSrsMode(state);
                return;
            }

            if (mode != _lastMode)
            {
                _lastMode = mode;
                Logger.Info("CHD SRS mode -> " + (mode ? "ON" : "OFF"));
                if (mode) ActivateSrsMode(state);
            }

            if (mode && active >= 1 && active <= 2 &&
                (Math.Abs(state.ActiveSequence - _lastActiveSeq) >= 0.5))
            {
                SelectSrsRadio(active);
                _lastActiveRadio = active;
                _lastActiveSeq = state.ActiveSequence;
            }

            if (Math.Abs(state.CommitSequence - _lastCommitSeq) >= 0.5)
            {
                _lastCommitSeq = state.CommitSequence;
                if (mode)
                {
                    if (selected == 1) CommitFrequency(_config.Radio1Id, state.Radio1FrequencyMHz, "SRS UHF1");
                    else if (selected == 2) CommitFrequency(_config.Radio2Id, state.Radio2FrequencyMHz, "SRS UHF2");
                }
            }

            if (Math.Abs(state.VolumeSequence - _lastVolumeSeq) >= 0.5)
            {
                _lastVolumeSeq = state.VolumeSequence;
                if (mode) CommitSelectedVolume(selected, state);
            }

            if (Math.Abs(state.IntercomSequence - _lastIntercomSeq) >= 0.5)
            {
                _lastIntercomSeq = state.IntercomSequence;
                if (mode) CommitIntercomChannel(state.IntercomChannel);
            }

            if (Math.Abs(state.EncryptionSequence - _lastEncryptionSeq) >= 0.5)
            {
                _lastEncryptionSeq = state.EncryptionSequence;
                if (mode)
                {
                    if (selected == 1) CommitEncryption(_config.Radio1Id, state.Radio1Encryption, state.Radio1EncryptionKey, "UHF1 encryption");
                    else if (selected == 2) CommitEncryption(_config.Radio2Id, state.Radio2Encryption, state.Radio2EncryptionKey, "UHF2 encryption");
                }
            }
        }

        private void ActivateSrsMode(SrsCockpitData state)
        {
            if (_config.SyncBothOnModeOn)
            {
                CommitFrequency(_config.Radio1Id, state.Radio1FrequencyMHz, "SRS UHF1 sync");
                CommitFrequency(_config.Radio2Id, state.Radio2FrequencyMHz, "SRS UHF2 sync");
            }
            CommitVolume(_config.Radio1Id, state.Radio1VolumePct, "UHF1 volume sync");
            CommitVolume(_config.Radio2Id, state.Radio2VolumePct, "UHF2 volume sync");
            CommitVolume(0, state.IntercomVolumePct, "Intercom volume sync");
            CommitIntercomChannel(state.IntercomChannel);

            int active = (int)Math.Round(state.ActiveRadio);
            if (active < 1 || active > 2) active = 1;
            SelectSrsRadio(active);
            _lastActiveRadio = active;
            _lastActiveSeq = state.ActiveSequence;
        }

        private void SelectSrsRadio(int cockpitRadio)
        {
            // ACT remains an explicit cockpit command. A value received from
            // SRS must not be echoed back as another radio-select command.
            _feedback.CockpitCommand(cockpitRadio, DateTime.UtcNow.Ticks);
            _pendingFeedback = 0;
            if (cockpitRadio == 1)
            {
                _srs.SelectRadio(_config.Radio1Id);
                Logger.Info("SRS active radio -> UHF1 (SRS RadioId " + _config.Radio1Id + ")");
            }
            else if (cockpitRadio == 2)
            {
                _srs.SelectRadio(_config.Radio2Id);
                Logger.Info("SRS active radio -> UHF2 (SRS RadioId " + _config.Radio2Id + ")");
            }
        }

        private void CommitSelectedVolume(int selected, SrsCockpitData state)
        {
            if (selected == 1) CommitVolume(_config.Radio1Id, state.Radio1VolumePct, "UHF1 volume");
            else if (selected == 2) CommitVolume(_config.Radio2Id, state.Radio2VolumePct, "UHF2 volume");
            else if (selected == 3) CommitVolume(0, state.IntercomVolumePct, "Intercom volume");
        }

        private void CommitVolume(int radioId, double pct, string label)
        {
            if (double.IsNaN(pct) || double.IsInfinity(pct)) return;
            if (pct < 0) pct = 0;
            if (pct > 100) pct = 100;
            _srs.SetVolume(radioId, pct / 100.0);
            Logger.Info(label + " -> " + pct.ToString("0", CultureInfo.InvariantCulture) + "%");
        }

        private void CommitIntercomChannel(double value)
        {
            int channel = (int)Math.Round(value);
            if (channel < 1 || channel > 99)
            {
                Logger.Warn("Rejected intercom channel: " + channel + " (allowed 1-99)");
                return;
            }
            _srs.SetIntercomChannel(channel);
            Logger.Info("SRS intercom channel -> " + channel);
        }

        private void CommitEncryption(int radioId, double enabledValue, double keyValue, string label)
        {
            if (Double.IsNaN(keyValue) || Double.IsInfinity(keyValue) || keyValue < 1 || keyValue > 252)
            { Logger.Warn("Rejected encryption key outside 1-252."); return; }
            int slot = radioId == _session.Radio1 ? 1 : radioId == _session.Radio2 ? 2 : 0;
            if (slot == 0) { Logger.Warn("Rejected unknown encryption radio."); return; }
            var request = new EFSRSLink.EncryptionRequest { Sequence = ++_encryptionRequest, Stamp = DateTime.UtcNow.Ticks,
                Radio = radioId, Key = (int)Math.Round(keyValue), Enabled = enabledValue >= 0.5 };
            EFSRSLink.Wire.Write(_session.CommandPath(slot), request.Encode(_session.Token));
            _issued[slot-1] = request.Sequence;
            Logger.Info(label + " requested -> " + (request.Enabled ? "ON" : "OFF") + ", key " + request.Key);
        }

        public void PollSrsFeedback()
        {
            try
            {
                string raw = EFSRSLink.Wire.ReadSmall(_session.FilePath("status.txt"));
                var state = EFSRSLink.Snapshot.Parse(raw, _session.Token, DateTime.UtcNow.Ticks);
                if (state == null) return;
                ReportEncryptionAck(0, state.Ack1, state.Result1);
                ReportEncryptionAck(1, state.Ack2, state.Result2);
                if (_sim == null || !_definitionRegistered || !_stateInitialized) return;
                int active = _feedback.Propose(state, _session.Radio1, _session.Radio2, DateTime.UtcNow.Ticks);
                if (active != 0)
                {
                    _sim.SetDataOnSimObject(Definitions.ActiveRadioFeedback, SimConnect.SIMCONNECT_OBJECT_ID_USER,
                        SIMCONNECT_DATA_SET_FLAG.DEFAULT, new ActiveRadioFeedback { ActiveRadio = active });
                    _feedback.LastApplied = active;
                    _pendingFeedback = active;
                    _lastActiveRadio = active;
                    Logger.Info("SRS selected -> HOLD UHF" + active);
                }
                _feedbackErrorLogged = false;
            }
            catch (Exception ex)
            {
                if (!_feedbackErrorLogged) Logger.Error("SRS feedback unavailable", ex);
                _feedbackErrorLogged = true;
            }
        }

        private void ReportEncryptionAck(int slot, long sequence, int result)
        {
            if (sequence <= _acknowledged[slot] || sequence > _issued[slot]) return;
            _acknowledged[slot] = sequence;
            string message = "UHF" + (slot + 1) + " ENC/KEY request " + sequence + ": ";
            if (result == 1) Logger.Info(message + "confirmed by SRS read-back");
            else Logger.Warn(message + (result == 2 ? "radio/server does not allow overlay encryption" :
                result == 3 ? "expired; connect EAM and retry" : "failed read-back; see hook.log"));
        }

        private void CommitFrequency(int radioId, double valueMHz, string label)
        {
            if (double.IsNaN(valueMHz) || double.IsInfinity(valueMHz) || valueMHz < 225.0 || valueMHz > 399.975)
            {
                Logger.Warn("Rejected " + label + " frequency: " + valueMHz.ToString("0.000", CultureInfo.InvariantCulture) + " MHz (allowed 225.000-399.975)");
                return;
            }
            _srs.SetFrequency(radioId, valueMHz);
            Logger.Info(label + " -> SRS radio " + radioId + ": " + valueMHz.ToString("0.000", CultureInfo.InvariantCulture) + " MHz");
        }

        private void OnRecvQuit(SimConnect sender, SIMCONNECT_RECV data)
        {
            Logger.Warn("MSFS closed/disconnected. Waiting to reconnect.");
            Disconnect();
        }

        private void OnRecvException(SimConnect sender, SIMCONNECT_RECV_EXCEPTION data)
        {
            Logger.Warn("SimConnect exception: " + ((SIMCONNECT_EXCEPTION)data.dwException));
        }

        private void Disconnect()
        {
            _definitionRegistered = false;
            _stateInitialized = false;
            _lastCommitSeq = 0;
            _lastVolumeSeq = 0;
            _lastIntercomSeq = 0;
            _lastActiveSeq = 0;
            _lastEncryptionSeq = 0;
            _lastActiveRadio = -1;
            _lastMode = false;
            _feedback = new EFSRSLink.FeedbackGate();
            _pendingFeedback = 0;
            if (_sim != null) { try { _sim.Dispose(); } catch { } _sim = null; }
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            Disconnect();
            _srs.Dispose();
        }
    }
}
