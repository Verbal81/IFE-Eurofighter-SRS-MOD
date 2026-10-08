using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace Microsoft.FlightSimulator.SimConnect
{
    public enum SIMCONNECT_DATATYPE { INVALID=0, INT32=1, INT64=2, FLOAT32=3, FLOAT64=4 }
    public enum SIMCONNECT_PERIOD { NEVER=0, ONCE=1, VISUAL_FRAME=2, SIM_FRAME=3, SECOND=4 }
    [Flags] public enum SIMCONNECT_DATA_REQUEST_FLAG { DEFAULT=0, CHANGED=1, TAGGED=2 }
    [Flags] public enum SIMCONNECT_DATA_SET_FLAG { DEFAULT=0, TAGGED=1 }
    public enum SIMCONNECT_EXCEPTION { NONE=0, ERROR=1, SIZE_MISMATCH=2, UNRECOGNIZED_ID=3, UNOPENED=4, VERSION_MISMATCH=5 }

    public class SIMCONNECT_RECV { public uint dwID; }
    public sealed class SIMCONNECT_RECV_OPEN : SIMCONNECT_RECV { }
    public sealed class SIMCONNECT_RECV_EXCEPTION : SIMCONNECT_RECV { public uint dwException; }
    public sealed class SIMCONNECT_RECV_SIMOBJECT_DATA : SIMCONNECT_RECV
    {
        public uint dwRequestID;
        public object[] dwData;
    }

    // Minimal native wrapper for the exact EF-SRS calls. No Microsoft managed SimConnect assembly is required.
    public sealed class SimConnect : IDisposable
    {
        public const uint SIMCONNECT_UNUSED = 0xFFFFFFFF;
        public const uint SIMCONNECT_OBJECT_ID_USER = 0;

        public event Action<SimConnect,SIMCONNECT_RECV_OPEN> OnRecvOpen;
        public event Action<SimConnect,SIMCONNECT_RECV> OnRecvQuit;
        public event Action<SimConnect,SIMCONNECT_RECV_EXCEPTION> OnRecvException;
        public event Action<SimConnect,SIMCONNECT_RECV_SIMOBJECT_DATA> OnRecvSimobjectData;

        private IntPtr _handle;
        private readonly Dictionary<uint,Type> _types = new Dictionary<uint,Type>();

        [DllImport("SimConnect.dll", CharSet=CharSet.Ansi)]
        private static extern int SimConnect_Open(out IntPtr phSimConnect, string szName, IntPtr hWnd, uint UserEventWin32, IntPtr hEventHandle, uint ConfigIndex);
        [DllImport("SimConnect.dll")] private static extern int SimConnect_Close(IntPtr hSimConnect);
        [DllImport("SimConnect.dll", CharSet=CharSet.Ansi)]
        private static extern int SimConnect_AddToDataDefinition(IntPtr h, uint defineId, string datumName, string unitsName, uint datumType, float epsilon, uint datumId);
        [DllImport("SimConnect.dll")]
        private static extern int SimConnect_RequestDataOnSimObject(IntPtr h, uint requestId, uint defineId, uint objectId, uint period, uint flags, uint origin, uint interval, uint limit);
        [DllImport("SimConnect.dll")]
        private static extern int SimConnect_SetDataOnSimObject(IntPtr h, uint defineId, uint objectId, uint flags, uint arrayCount, uint cbUnitSize, IntPtr data);
        [DllImport("SimConnect.dll")]
        private static extern int SimConnect_GetNextDispatch(IntPtr h, out IntPtr ppData, out uint pcbData);

        private static void Check(int hr, string op)
        {
            if (hr < 0) Marshal.ThrowExceptionForHR(hr);
        }

        public SimConnect(string name, IntPtr windowHandle, uint userMessage, object eventHandle, uint configIndex)
        {
            IntPtr h;
            int hr = SimConnect_Open(out h, name, windowHandle, userMessage, IntPtr.Zero, configIndex);
            Check(hr, "SimConnect_Open");
            _handle = h;
        }

        private static uint Id(object value) { return Convert.ToUInt32(value); }

        public void AddToDataDefinition(object defineId, string datumName, string unitsName, SIMCONNECT_DATATYPE type, float epsilon, uint datumId)
        {
            Check(SimConnect_AddToDataDefinition(_handle, Id(defineId), datumName, unitsName, (uint)type, epsilon, datumId), "AddToDataDefinition");
        }

        public void RegisterDataDefineStruct<T>(object defineId) where T:struct { _types[Id(defineId)] = typeof(T); }

        public void RequestDataOnSimObject(object requestId, object defineId, uint objectId, SIMCONNECT_PERIOD period,
            SIMCONNECT_DATA_REQUEST_FLAG flags, uint origin, uint interval, uint limit)
        {
            Check(SimConnect_RequestDataOnSimObject(_handle, Id(requestId), Id(defineId), objectId, (uint)period, (uint)flags, origin, interval, limit), "RequestDataOnSimObject");
        }

        public void SetDataOnSimObject<T>(object defineId, uint objectId, SIMCONNECT_DATA_SET_FLAG flags, T value) where T:struct
        {
            int size=Marshal.SizeOf(typeof(T));
            IntPtr p=Marshal.AllocHGlobal(size);
            try {
                Marshal.StructureToPtr(value,p,false);
                Check(SimConnect_SetDataOnSimObject(_handle,Id(defineId),objectId,(uint)flags,0,(uint)size,p),"SetDataOnSimObject");
            } finally { Marshal.FreeHGlobal(p); }
        }

        public void ReceiveMessage()
        {
            if (_handle==IntPtr.Zero) return;
            while (true)
            {
                IntPtr p; uint cb;
                int hr=SimConnect_GetNextDispatch(_handle,out p,out cb);
                if (hr < 0 || p==IntPtr.Zero || cb < 12) return;
                uint id=(uint)Marshal.ReadInt32(p,8);
                if (id==2) {
                    var x=new SIMCONNECT_RECV_OPEN(); x.dwID=id;
                    if(OnRecvOpen!=null) OnRecvOpen(this,x);
                } else if (id==3) {
                    var x=new SIMCONNECT_RECV(); x.dwID=id;
                    if(OnRecvQuit!=null) OnRecvQuit(this,x);
                } else if (id==1) {
                    var x=new SIMCONNECT_RECV_EXCEPTION(); x.dwID=id; x.dwException=(uint)Marshal.ReadInt32(p,12);
                    if(OnRecvException!=null) OnRecvException(this,x);
                } else if (id==8 && cb>=44) {
                    uint request=(uint)Marshal.ReadInt32(p,12);
                    uint define=(uint)Marshal.ReadInt32(p,20);
                    Type t;
                    if(_types.TryGetValue(define,out t)) {
                        // SIMCONNECT_RECV (12 bytes) + seven DWORD fields; dwData starts at byte 40.
                        IntPtr data=IntPtr.Add(p,40);
                        object state=Marshal.PtrToStructure(data,t);
                        var x=new SIMCONNECT_RECV_SIMOBJECT_DATA();
                        x.dwID=id; x.dwRequestID=request; x.dwData=new object[]{state};
                        if(OnRecvSimobjectData!=null) OnRecvSimobjectData(this,x);
                    }
                }
            }
        }

        public void Dispose()
        {
            if(_handle!=IntPtr.Zero) {
                try { SimConnect_Close(_handle); } catch {}
                _handle=IntPtr.Zero;
            }
        }
    }
}
