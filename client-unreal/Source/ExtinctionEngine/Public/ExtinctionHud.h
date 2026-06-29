#pragma once

#include "CoreMinimal.h"
#include "GameFramework/HUD.h"
#include "ExtinctionHud.generated.h"

UCLASS()
class EXTINCTIONENGINE_API AExtinctionHud : public AHUD
{
	GENERATED_BODY()

public:
	virtual void DrawHUD() override;

	bool IsQuitButtonHit(const FVector2D& ScreenPosition) const;

private:
	FBox2D QuitButtonBounds;

	void DrawDiagnostics();
	void DrawEscMenu();
};
