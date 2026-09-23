// SoftwareGuardian.exe: runs the embedded clean_software.ps1 inside this process, so there is no
// console window, no execution-policy prompt, and no temp copy of the script that another program
// could swap out before it runs as Administrator.
using System;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Threading;
using System.Windows.Forms;

static class Launcher
{
    [STAThread]
    static void Main()
    {
        string script;
        using (var reader = new StreamReader(Assembly.GetExecutingAssembly().GetManifestResourceStream("clean_software.ps1")))
            script = reader.ReadToEnd();

        using (Runspace runspace = RunspaceFactory.CreateRunspace())
        using (PowerShell ps = PowerShell.Create())
        {
            runspace.ApartmentState = ApartmentState.STA;          // WinForms needs an STA thread
            runspace.ThreadOptions = PSThreadOptions.UseCurrentThread;
            runspace.Open();
            ps.Runspace = runspace;
            ps.AddScript(script).AddParameter("LogDir", AppDomain.CurrentDomain.BaseDirectory);
            try { ps.Invoke(); }
            catch (Exception e) { MessageBox.Show(e.Message, "Universal Software Guardian"); }
        }
    }
}
