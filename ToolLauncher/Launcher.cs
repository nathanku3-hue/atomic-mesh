using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

public class Program
{
    public static void Main(string[] args)
    {
        // Look for Launcher.ps1 in the same directory as this EXE
        string scriptPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Launcher.ps1");
        
        if (!File.Exists(scriptPath))
        {
            MessageBox.Show("Launcher.ps1 not found!\nExpected at: " + scriptPath, "Launcher Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        // Construct arguments string
        string scriptArgs = "";
        if (args.Length > 0)
        {
            scriptArgs = " " + string.Join(" ", args);
        }

        ProcessStartInfo startInfo = new ProcessStartInfo();
        startInfo.FileName = "powershell.exe";
        // Run the script hidden, bypassing execution policy, and passing any arguments (like -AutoLaunch)
        startInfo.Arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + scriptPath + "\"" + scriptArgs;
        
        // "runas" triggers the UAC prompt for Administrator privileges
        startInfo.Verb = "runas"; 
        startInfo.UseShellExecute = true;
        startInfo.WindowStyle = ProcessWindowStyle.Hidden;

        try
        {
            Process.Start(startInfo);
        }
        catch (System.ComponentModel.Win32Exception)
        {
            // User likely cancelled the UAC prompt; do nothing or show message
        }
        catch (Exception ex)
        {
            MessageBox.Show("Failed to start launcher: " + ex.Message, "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}
