using UnrealBuildTool;
using System.Collections.Generic;

public class QuantumTeleportarTarget : TargetRules
{
    public QuantumTeleportarTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Game;
        DefaultBuildSettings = BuildSettingsVersion.Latest;
        IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
        ExtraModuleNames.Add("QuantumTeleportar");
    }
}
