using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

internal static class Program
{
    internal const string AppName = "제비뽑기";
    private const string BundleResource = "Draw.Payload.zip";
    private static string runtimeFolder;

    [STAThread]
    private static void Main()
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);

        try
        {
            string dataFolder = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                AppName);
            string packageFolder = PreparePackage(dataFolder);
            runtimeFolder = Path.Combine(packageFolder, "runtime");
            AppDomain.CurrentDomain.AssemblyResolve += ResolveWebView2Assembly;
            RunWindow(dataFolder, Path.Combine(packageFolder, "web"));
        }
        catch (Exception error)
        {
            MessageBox.Show("앱을 시작할 수 없습니다.\n" + error.Message,
                AppName, MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    // Keep the WebView2-dependent code separate until the DLL resolver is registered.
    [MethodImpl(MethodImplOptions.NoInlining)]
    private static void RunWindow(string dataFolder, string webFolder)
    {
        CoreWebView2Environment.SetLoaderDllFolderPath(runtimeFolder);
        using (var window = new DrawWindow(dataFolder, webFolder))
            Application.Run(window);
    }

    private static Assembly ResolveWebView2Assembly(object sender, ResolveEventArgs args)
    {
        string name = new AssemblyName(args.Name).Name;
        if (name != "Microsoft.Web.WebView2.Core" && name != "Microsoft.Web.WebView2.WinForms")
            return null;
        return Assembly.LoadFrom(Path.Combine(runtimeFolder, name + ".dll"));
    }

    private static string PreparePackage(string dataFolder)
    {
        using (Stream payload = Assembly.GetExecutingAssembly().GetManifestResourceStream(BundleResource))
        using (SHA256 sha = SHA256.Create())
        {
            if (payload == null) throw new InvalidDataException("내장 파일을 찾을 수 없습니다.");
            string hash = BitConverter.ToString(sha.ComputeHash(payload), 0, 12).Replace("-", "");
            string packages = Path.Combine(dataFolder, "Packages");
            Directory.CreateDirectory(packages);
            string package = Path.Combine(packages, hash);
            if (Directory.Exists(package)) return package;

            string staging = Path.Combine(packages, hash + "-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(staging);
            try
            {
                payload.Position = 0;
                using (var archive = new ZipArchive(payload, ZipArchiveMode.Read, true))
                {
                    string prefix = staging + Path.DirectorySeparatorChar;
                    foreach (ZipArchiveEntry entry in archive.Entries)
                    {
                        string destination = Path.GetFullPath(Path.Combine(staging, entry.FullName));
                        if (!destination.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                            throw new InvalidDataException("내장 파일 경로가 올바르지 않습니다.");

                        Directory.CreateDirectory(Path.GetDirectoryName(destination));
                        entry.ExtractToFile(destination);
                    }
                }

                try { Directory.Move(staging, package); }
                catch (IOException) { if (!Directory.Exists(package)) throw; }
                return package;
            }
            finally
            {
                if (Directory.Exists(staging)) Directory.Delete(staging, true);
            }
        }
    }
}

internal sealed class DrawWindow : Form
{
    private const string AssetHost = "jebidraw.example";
    private const string AssetOrigin = "https://" + AssetHost;
    private const string StorageKey = "speaking-draw-v4";
    private const string MigrationMessage = "draw-migration-complete";
    private const string RuntimeDownloadUrl = "https://developer.microsoft.com/microsoft-edge/webview2/#download-section";
    private const int MaxMigrationBytes = 8 * 1024 * 1024;

    private readonly string dataFolder;
    private readonly string webFolder;
    private readonly WebView2 webView;
    private readonly Label loadingLabel;

    internal DrawWindow(string dataFolder, string webFolder)
    {
        this.dataFolder = dataFolder;
        this.webFolder = webFolder;

        Text = Program.AppName;
        Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
        StartPosition = FormStartPosition.CenterScreen;
        AutoScaleMode = AutoScaleMode.Dpi;
        ClientSize = new Size(1120, 780);
        MinimumSize = new Size(380, 560);
        BackColor = Color.FromArgb(238, 241, 246);

        webView = new WebView2 { Dock = DockStyle.Fill, Visible = false };
        loadingLabel = new Label
        {
            Text = "제비뽑기를 여는 중…",
            TextAlign = ContentAlignment.MiddleCenter,
            Dock = DockStyle.Fill,
            Font = new Font("맑은 고딕", 13)
        };
        Controls.Add(webView);
        Controls.Add(loadingLabel);
        Shown += OpenApp;
    }

    private async void OpenApp(object sender, EventArgs args)
    {
        try
        {
            string profileFolder = Path.Combine(dataFolder, "WebView2");
            var environment = await CoreWebView2Environment.CreateAsync(null, profileFolder);
            if (IsDisposed) return;
            await webView.EnsureCoreWebView2Async(environment);
            if (IsDisposed) return;

            CoreWebView2 core = webView.CoreWebView2;
            core.Settings.UserAgent += " DrawWebView2/1.0";
            core.SetVirtualHostNameToFolderMapping(AssetHost, webFolder,
                CoreWebView2HostResourceAccessKind.Deny);
            core.NavigationStarting += (source, navigation) =>
            {
                if (!IsAppUrl(navigation.Uri)) navigation.Cancel = true;
            };
            core.NewWindowRequested += (source, request) => request.Handled = true;
            core.NavigationCompleted += NavigationCompleted;
            await PrepareMigration(core);
            if (!IsDisposed) core.Navigate(AssetOrigin + "/index.html");
        }
        catch (WebView2RuntimeNotFoundException)
        {
            if (IsDisposed) return;
            loadingLabel.Text = "Microsoft Edge WebView2 런타임이 필요합니다.";
            DialogResult result = MessageBox.Show(this,
                "Microsoft Edge WebView2 런타임을 설치한 뒤 다시 실행하세요.\n다운로드 페이지를 열까요?",
                Program.AppName, MessageBoxButtons.YesNo, MessageBoxIcon.Information);
            if (result == DialogResult.Yes)
            {
                try
                {
                    Process.Start(new ProcessStartInfo(RuntimeDownloadUrl) { UseShellExecute = true });
                }
                catch (Exception)
                {
                    MessageBox.Show(this, RuntimeDownloadUrl, Program.AppName);
                }
            }
            Close();
        }
        catch (Exception error)
        {
            if (IsDisposed) return;
            loadingLabel.Text = "제비뽑기를 열 수 없습니다.";
            MessageBox.Show(this, error.Message, Program.AppName,
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private static bool IsAppUrl(string address)
    {
        Uri uri;
        return Uri.TryCreate(address, UriKind.Absolute, out uri) &&
            uri.Scheme == Uri.UriSchemeHttps && uri.IdnHost == AssetHost &&
            uri.IsDefaultPort && uri.UserInfo.Length == 0;
    }

    private void NavigationCompleted(object sender, CoreWebView2NavigationCompletedEventArgs args)
    {
        if (!args.IsSuccess)
        {
            loadingLabel.Text = "앱 화면을 불러오지 못했습니다.";
            return;
        }
        loadingLabel.Visible = false;
        webView.Visible = true;
    }

    private async Task PrepareMigration(CoreWebView2 core)
    {
        string migrationPath = Path.Combine(dataFolder, "migration.json");
        string markerPath = Path.Combine(dataFolder, "migration.imported");
        if (File.Exists(markerPath) || !File.Exists(migrationPath)) return;

        string json;
        try
        {
            using (var stream = File.OpenRead(migrationPath))
            {
                if (stream.Length > MaxMigrationBytes) return;
                using (var reader = new StreamReader(stream, Encoding.UTF8))
                    json = reader.ReadToEnd();
            }
            var serializer = new JavaScriptSerializer { MaxJsonLength = MaxMigrationBytes };
            var state = serializer.DeserializeObject(json) as Dictionary<string, object>;
            if (!HasArray(state, "room9") || !HasArray(state, "room11") ||
                !HasArray(state, "customTabs")) return;
        }
        catch (IOException) { return; }
        catch (UnauthorizedAccessException) { return; }
        catch (ArgumentException) { return; }
        catch (InvalidOperationException) { return; }

        string base64 = Convert.ToBase64String(Encoding.UTF8.GetBytes(json));
        string script = "(function(){if(window.top!==window||location.origin!=='" + AssetOrigin +
            "')return;try{if(localStorage.getItem('" + StorageKey + "')===null){" +
            "const bytes=Uint8Array.from(atob('" + base64 + "'),c=>c.charCodeAt(0));" +
            "localStorage.setItem('" + StorageKey + "',new TextDecoder().decode(bytes));}" +
            "window.chrome.webview.postMessage('" + MigrationMessage + "');}catch(_){}})();";
        string scriptId = await core.AddScriptToExecuteOnDocumentCreatedAsync(script);
        if (IsDisposed) return;

        core.WebMessageReceived += (sender, args) =>
        {
            if (!IsAppUrl(args.Source) ||
                args.WebMessageAsJson != "\"" + MigrationMessage + "\"") return;
            try
            {
                File.WriteAllText(markerPath, "imported", Encoding.ASCII);
                core.RemoveScriptToExecuteOnDocumentCreated(scriptId);
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        };
    }

    private static bool HasArray(Dictionary<string, object> state, string name)
    {
        object value;
        return state != null && state.TryGetValue(name, out value) && value is IList;
    }
}
