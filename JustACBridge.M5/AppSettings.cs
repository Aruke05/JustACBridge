using System.Text.Json;

namespace JustACBridgeM5;

internal sealed record AppSettings(TriggerSetting Lossless, TriggerSetting PreserveBurst)
{
    private static readonly string SettingsDirectory =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "JustACBridge.M5");
    private static readonly string SettingsPath = Path.Combine(SettingsDirectory, "settings.json");

    internal static AppSettings Default => new(
        TriggerSetting.From(TriggerBinding.M5),
        TriggerSetting.From(TriggerBinding.M4));

    internal static AppSettings Load()
    {
        try
        {
            if (!File.Exists(SettingsPath)) return Default;
            AppSettings? settings = JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(SettingsPath));
            if (settings is null) return Default;
            TriggerBinding lossless = settings.Lossless.ToBinding();
            TriggerBinding preserve = settings.PreserveBurst.ToBinding();
            return lossless == preserve ? Default : settings;
        }
        catch
        {
            return Default;
        }
    }

    internal void Save()
    {
        try
        {
            Directory.CreateDirectory(SettingsDirectory);
            string json = JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(SettingsPath, json);
        }
        catch
        {
            // Mapping remains active for this session even if settings cannot be persisted.
        }
    }
}

internal sealed record TriggerSetting(TriggerKind Kind, uint Code)
{
    internal static TriggerSetting From(TriggerBinding binding) => new(binding.Kind, binding.Code);

    internal TriggerBinding ToBinding()
    {
        if (Kind == TriggerKind.XButton && Code is NativeMethods.XBUTTON1 or NativeMethods.XBUTTON2)
            return new TriggerBinding(Kind, Code);
        if (Kind == TriggerKind.Keyboard && Code is > 0 and <= 0xFE)
            return new TriggerBinding(Kind, Code);
        throw new InvalidDataException("Invalid trigger binding.");
    }
}
