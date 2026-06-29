#pragma once

#include "CoreMinimal.h"
#include "GameFramework/PlayerController.h"
#include "ExtinctionPlayerController.generated.h"

UCLASS()
class EXTINCTIONENGINE_API AExtinctionPlayerController : public APlayerController
{
	GENERATED_BODY()

public:
	virtual void BeginPlay() override;
	virtual void PlayerTick(float DeltaTime) override;

	bool IsMenuOpen() const { return bMenuOpen; }

private:
	bool bMenuOpen = false;
	bool bWasEscapeDown = false;
	bool bWasLeftMouseDown = false;

	void ToggleMenu();
	void SetMenuOpen(bool bOpen);
	void HandleMenuClick();
};
