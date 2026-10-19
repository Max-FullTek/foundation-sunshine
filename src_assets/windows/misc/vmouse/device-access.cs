// Copyright (c) 2026 Foundation contributors. SPDX-License-Identifier: MS-PL.
// Native helpers for the paired installer. No service or package operations.
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public static class FoundationDeviceAccess {
    [DllImport("cfgmgr32.dll", CharSet=CharSet.Unicode)] static extern uint CM_Get_Device_Interface_List_SizeW(out uint length, ref Guid guid, string instance, uint flags);
    [DllImport("cfgmgr32.dll", CharSet=CharSet.Unicode)] static extern uint CM_Get_Device_Interface_ListW(ref Guid guid, string instance, [Out] char[] data, uint length, uint flags);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern SafeFileHandle CreateFileW(string path, uint access, uint share, IntPtr attributes, uint creation, uint flags, IntPtr template);
    [DllImport("advapi32.dll")] static extern uint GetSecurityInfo(SafeFileHandle handle, uint type, uint information, IntPtr owner, IntPtr group, IntPtr dacl, IntPtr sacl, out IntPtr descriptor);
    [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool ConvertSecurityDescriptorToStringSecurityDescriptorW(IntPtr descriptor, uint revision, uint information, out IntPtr text, IntPtr length);
    [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr memory);
    static void Check(bool ok) { if (!ok) throw new Win32Exception(Marshal.GetLastWin32Error()); }
    public static string[] HidPaths(string instance) {
        Guid guid = new Guid("4d1e55b2-f16f-11cf-88cb-001111000030");
        uint length; uint status = CM_Get_Device_Interface_List_SizeW(out length, ref guid, instance, 0);
        if (status != 0) throw new InvalidOperationException("CM interface size: " + status);
        char[] data = new char[length];
        status = CM_Get_Device_Interface_ListW(ref guid, instance, data, length, 0);
        if (status != 0) throw new InvalidOperationException("CM interface list: " + status);
        return new string(data).Split(new char[]{'\0'}, StringSplitOptions.RemoveEmptyEntries);
    }
    public static string ReadSecurity(string path) {
        using (SafeFileHandle file = CreateFileW(path, 0x20000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero)) {
            if (file.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
            IntPtr descriptor; uint error = GetSecurityInfo(file, 6, 7, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, out descriptor);
            if (error != 0) throw new Win32Exception((int)error);
            IntPtr text = IntPtr.Zero;
            try {
                Check(ConvertSecurityDescriptorToStringSecurityDescriptorW(descriptor, 1, 7, out text, IntPtr.Zero));
                return Marshal.PtrToStringUni(text);
            } finally { if (text != IntPtr.Zero) LocalFree(text); LocalFree(descriptor); }
        }
    }
}
