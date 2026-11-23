using System;
using System.Runtime.InteropServices;

public static class CodexTaskbar {
  [StructLayout(LayoutKind.Sequential)]
  struct Key { public Guid format; public uint id; }
  [StructLayout(LayoutKind.Sequential)]
  struct Value { public ushort type, r1, r2, r3; public IntPtr pointer; public int padding; }
  [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface Store {
    void GetCount(out uint count);
    void GetAt(uint index, out Key key);
    void GetValue(ref Key key, out Value value);
    void SetValue(ref Key key, ref Value value);
    void Commit();
  }
  delegate bool Visit(IntPtr window, IntPtr arg);
  [DllImport("shell32.dll")] static extern int SHGetPropertyStoreForWindow(IntPtr window, ref Guid iid, out Store store);
  [DllImport("ole32.dll")] static extern int PropVariantClear(ref Value value);
  [DllImport("user32.dll")] static extern bool EnumWindows(Visit visit, IntPtr arg);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
  [DllImport("user32.dll")] static extern bool IsIconic(IntPtr window);
  [DllImport("user32.dll")] static extern bool ShowWindowAsync(IntPtr window, int command);
  [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr window);
  [DllImport("user32.dll")] static extern int GetClassName(IntPtr window, System.Text.StringBuilder name, int length);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);

  public static int SetIdentity(int pid, string appId, bool focus) {
    int applied = 0;
    EnumWindows(delegate(IntPtr window, IntPtr arg) {
      uint owner;
      GetWindowThreadProcessId(window, out owner);
      if (owner != (uint)pid || !IsWindowVisible(window)) return true;
      var name = new System.Text.StringBuilder(64);
      GetClassName(window, name, name.Capacity);
      if (name.ToString() != "Chrome_WidgetWin_1") return true;
      var iid = typeof(Store).GUID;
      Store store;
      if (SHGetPropertyStoreForWindow(window, ref iid, out store) != 0) return true;
      var key = new Key { format = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), id = 5 };
      try {
        Value value;
        store.GetValue(ref key, out value);
        string existing;
        try { existing = value.type == 31 ? Marshal.PtrToStringUni(value.pointer) : null; }
        finally { PropVariantClear(ref value); }
        if (existing != appId) {
          value = new Value { type = 31, pointer = Marshal.StringToCoTaskMemUni(appId) };
          try { store.SetValue(ref key, ref value); store.Commit(); }
          finally { Marshal.FreeCoTaskMem(value.pointer); }
        }
        applied++;
        if (focus) {
          if (IsIconic(window)) ShowWindowAsync(window, 9);
          SetForegroundWindow(window);
          focus = false;
        }
      } catch (COMException) {} finally { Marshal.ReleaseComObject(store); }
      return true;
    }, IntPtr.Zero);
    return applied;
  }
}
