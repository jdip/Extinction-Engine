using UnrealBuildTool;

public class ExtinctionEngine : ModuleRules
{
	public ExtinctionEngine(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;

		PublicDependencyModuleNames.AddRange(new[]
		{
			"Core",
			"CoreUObject",
			"Engine",
			"InputCore",
			"Sockets",
			"Networking"
		});
	}
}

