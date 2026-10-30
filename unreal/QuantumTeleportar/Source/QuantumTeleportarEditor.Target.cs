using UnrealBuildTool;
using System.Collections.Generic;

public class QuantumTeleportarEditorTarget : TargetRules
{
    public QuantumTeleportarEditorTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Editor;
        DefaultBuildSettings = BuildSettingsVersion.Latest;
        IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
        ExtraModuleNames.Add("QuantumTeleportar");
    }
}
