using System.Diagnostics;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Threading.Channels;
using Velopack;
using Velopack.Sources;

namespace JajuchaGodotSimulator.Launcher;

internal static class Program
{
    private const string PackId = "Netherite1701.JajuchaGodotSimulator";
    private const string Repository = "https://github.com/Netherite1701/jajucha-godot-simulator";
    private const string SimulatorExe = "JajuchaGodotSimulatorApp.exe";
    private const string PipeName = "JajuchaGodotSimulator.Updates";
    private static readonly Channel<bool> Checks = Channel.CreateUnbounded<bool>();
    private static Process? _simulator;
    private static NotifyIcon? _tray;
    private static Control? _uiDispatcher;
    private static UpdateManager? _updates;
    private static readonly CancellationTokenSource Cancellation = new();

    [STAThread]
    private static int Main(string[] args)
    {
        VelopackApp.Build().SetAutoApplyOnStartup(false).Run();
        if (args.Contains("--check-updates", StringComparer.OrdinalIgnoreCase))
            return RequestCheck();

        var appDirectory = AppContext.BaseDirectory;
        Environment.SetEnvironmentVariable("JAJUCHA_LAUNCHER", Environment.ProcessPath);
        Environment.SetEnvironmentVariable("JAJUCHA_PYTHON", Path.Combine(appDirectory, "python", "python.exe"));
        var dataDirectory = Environment.GetEnvironmentVariable("JAJUCHA_DATA_DIR");
        if (string.IsNullOrWhiteSpace(dataDirectory))
            dataDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "JajuchaGodotSimulatorData");
        Environment.SetEnvironmentVariable("JAJUCHA_DATA_DIR", dataDirectory);
        if (args.Contains("--self-test-controls", StringComparer.OrdinalIgnoreCase))
            return RunPackagedTest(appDirectory, lap: false, controls: true);
        if (args.Contains("--self-test", StringComparer.OrdinalIgnoreCase))
            return RunPackagedTest(appDirectory, lap: false, controls: false);
        if (args.Contains("--self-test-lap", StringComparer.OrdinalIgnoreCase))
            return RunPackagedTest(appDirectory, lap: true, controls: false);
        if (args.Contains("--self-test-notebook", StringComparer.OrdinalIgnoreCase))
            return RunPackagedTest(appDirectory, lap: false, controls: false, notebook: true);

        ApplicationConfiguration.Initialize();
        _uiDispatcher = new Control();
        _ = _uiDispatcher.Handle;
        var executable = Path.Combine(AppContext.BaseDirectory, SimulatorExe);
        if (!File.Exists(executable))
        {
            MessageBox.Show($"The simulator files are missing:\n{executable}\n\nRepair the application from Windows Settings → Apps.", "Jajucha Simulator", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 2;
        }
        _updates = new UpdateManager(new GithubSource(Repository, accessToken: null, prerelease: false));
        using var process = StartSimulator(executable);
        if (process is null) return 3;
        _simulator = process;
        using var form = new ApplicationContextForm();
        _tray = form.Tray;
        process.EnableRaisingEvents = true;
        process.Exited += (_, _) => form.ExitThread();
        _ = ServeUpdateRequestsAsync(Cancellation.Token);
        _ = RunUpdateLoopAsync(Cancellation.Token);
        Application.Run(form);
        Cancellation.Cancel();
        _tray.Visible = false;
        _tray.Dispose();
        return process.ExitCode;
    }

    private static int RunPackagedTest(string appDirectory, bool lap, bool controls, bool notebook = false)
    {
        var executable = Path.Combine(appDirectory, SimulatorExe);
        if (!File.Exists(executable))
        {
            Console.Error.WriteLine($"Simulator executable not found: {executable}");
            return 2;
        }
        var start = new ProcessStartInfo(executable) { WorkingDirectory = appDirectory, UseShellExecute = false };
        if (controls)
        {
            start.ArgumentList.Add("--");
            start.ArgumentList.Add("--self-test-controls");
        }
        else if (lap)
        {
            start.ArgumentList.Add("--");
            start.ArgumentList.Add("--self-test-lap");
        }
        else if (notebook)
        {
            start.ArgumentList.Add("--");
            start.ArgumentList.Add("--self-test-notebook");
        }
        else
        {
            start.ArgumentList.Add("--headless");
            start.ArgumentList.Add("--");
            start.ArgumentList.Add("--self-test");
        }
        using var process = Process.Start(start);
        if (process is null) return 3;
        process.WaitForExit();
        return process.ExitCode;
    }

    private static Process? StartSimulator(string executable)
    {
        try
        {
            return Process.Start(new ProcessStartInfo(executable) { WorkingDirectory = AppContext.BaseDirectory, UseShellExecute = false });
        }
        catch (Exception error)
        {
            MessageBox.Show(error.Message, "Could not start Jajucha Simulator", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return null;
        }
    }

    private static int RequestCheck()
    {
        try
        {
            using var pipe = new NamedPipeClientStream(".", PipeName, PipeDirection.Out, PipeOptions.None);
            pipe.Connect(1500);
            using var writer = new StreamWriter(pipe) { AutoFlush = true };
            writer.WriteLine("check");
            return 0;
        }
        catch
        {
            MessageBox.Show("The simulator update service is not running. Start Jajucha Simulator and try again.", "Jajucha Simulator", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return 1;
        }
    }

    private static async Task ServeUpdateRequestsAsync(CancellationToken cancellation)
    {
        while (!cancellation.IsCancellationRequested)
        {
            try
            {
                await using var pipe = new NamedPipeServerStream(PipeName, PipeDirection.In, 1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous);
                await pipe.WaitForConnectionAsync(cancellation);
                using var reader = new StreamReader(pipe);
                if ((await reader.ReadLineAsync(cancellation)) == "check")
                    await Checks.Writer.WriteAsync(true, cancellation);
            }
            catch (OperationCanceledException) { return; }
            catch (IOException) { await Task.Delay(250, cancellation); }
        }
    }

    private static async Task RunUpdateLoopAsync(CancellationToken cancellation)
    {
        await Checks.Writer.WriteAsync(true, cancellation); // startup check
        while (!cancellation.IsCancellationRequested)
        {
            try
            {
                using var cycle = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
                var tick = Task.Delay(TimeSpan.FromHours(6), cycle.Token);
                var request = Checks.Reader.ReadAsync(cycle.Token).AsTask();
                await Task.WhenAny(tick, request);
                cycle.Cancel();
                while (Checks.Reader.TryRead(out _)) { }
                var update = await _updates!.CheckForUpdatesAsync();
                if (update is null) continue;
                var note = update.TargetFullRelease.NotesMarkdown;
                var choice = await ShowUpdatePromptAsync(update.TargetFullRelease.Version.ToString(), note);
                if (!choice) continue;
                await _updates.DownloadUpdatesAsync(update, value => SetTrayText($"Downloading update: {value}%"), cancellation);
                if (_simulator is { HasExited: false } app)
                {
                    app.CloseMainWindow();
                    using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(30));
                    try { await app.WaitForExitAsync(timeout.Token); }
                    catch (OperationCanceledException)
                    {
                        var retry = await ShowClosePromptAsync();
                        if (!retry) continue;
                        app.Kill(entireProcessTree: true);
                        await app.WaitForExitAsync();
                    }
                }
                _updates.ApplyUpdatesAndRestart(update);
                return;
            }
            catch (OperationCanceledException) { return; }
            catch (Exception error)
            {
                SetTrayText("Update check failed · simulator is still available");
                Debug.WriteLine($"Jajucha update check: {error}");
            }
        }
    }

    private static Task<bool> ShowUpdatePromptAsync(string version, string notes)
    {
        return OnUiAsync(() =>
        {
            using var form = new Form { Text = "Jajucha update available", Width = 520, Height = 380, StartPosition = FormStartPosition.CenterScreen, FormBorderStyle = FormBorderStyle.FixedDialog, MaximizeBox = false, MinimizeBox = false, TopMost = true };
            var text = new TextBox { Multiline = true, ReadOnly = true, WordWrap = true, ScrollBars = ScrollBars.Vertical, Dock = DockStyle.Fill, Text = $"Version {version} is ready.\r\n\r\n{(string.IsNullOrWhiteSpace(notes) ? "No release notes were provided." : notes)}\r\n\r\nThe simulator will save recovery data, stop the vehicle, and restart after the update." };
            var buttons = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 48, FlowDirection = FlowDirection.RightToLeft, Padding = new Padding(8) };
            var later = new Button { Text = "Later", DialogResult = DialogResult.No, Width = 100 };
            var update = new Button { Text = "Update and restart", DialogResult = DialogResult.Yes, Width = 150 };
            buttons.Controls.Add(later); buttons.Controls.Add(update);
            form.Controls.Add(text); form.Controls.Add(buttons); form.AcceptButton = update; form.CancelButton = later;
            form.Shown += (_, _) => SetTrayText($"Update {version} available");
            return form.ShowDialog() == DialogResult.Yes;
        });
    }

    private static Task<bool> ShowClosePromptAsync()
    {
        return OnUiAsync(() => MessageBox.Show("The simulator is still closing. Close it now to install the update? Any unsaved notebook changes are kept in recovery data.", "Jajucha update", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) == DialogResult.Yes);
    }

    private static void SetTrayText(string message)
    {
        if (_tray is null) return;
        var shortText = message.Length > 63 ? message[..63] : message;
        if (_uiDispatcher is { IsHandleCreated: true } dispatcher)
        {
            try { dispatcher.BeginInvoke(() => { if (_tray is not null) _tray.Text = shortText; }); }
            catch (InvalidOperationException) { }
        }
    }

    private static Task<T> OnUiAsync<T>(Func<T> action)
    {
        var completion = new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);
        try
        {
            _uiDispatcher!.BeginInvoke(() =>
            {
                try { completion.TrySetResult(action()); }
                catch (Exception error) { completion.TrySetException(error); }
            });
        }
        catch (Exception error) { completion.TrySetException(error); }
        return completion.Task;
    }

    private sealed class ApplicationContextForm : ApplicationContext, IDisposable
    {
        public NotifyIcon Tray { get; }
        private readonly System.Windows.Forms.Timer _exitTimer;
        public ApplicationContextForm()
        {
            var menu = new ContextMenuStrip();
            menu.Items.Add("Check for updates", null, (_, _) => Checks.Writer.TryWrite(true));
            menu.Items.Add("Exit simulator and updater", null, (_, _) => _simulator?.CloseMainWindow());
            Tray = new NotifyIcon { Icon = SystemIcons.Application, Text = "Jajucha Simulator", ContextMenuStrip = menu, Visible = true };
            Tray.DoubleClick += (_, _) => SetTrayText("Jajucha Simulator is running");
            _exitTimer = new System.Windows.Forms.Timer { Interval = 500 };
            _exitTimer.Tick += (_, _) => { if (_simulator is { HasExited: true }) ExitThread(); };
            _exitTimer.Start();
        }
        public new void Dispose() { _exitTimer.Stop(); _exitTimer.Dispose(); Tray.Dispose(); }
    }
}
