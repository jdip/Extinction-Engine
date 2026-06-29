#include "ExtinctionPlayerController.h"

#include "ExtinctionHud.h"
#include "HAL/PlatformMisc.h"
#include "InputCoreTypes.h"

void AExtinctionPlayerController::BeginPlay()
{
	Super::BeginPlay();
	SetMenuOpen(false);
}

void AExtinctionPlayerController::PlayerTick(float DeltaTime)
{
	Super::PlayerTick(DeltaTime);

	const bool bEscapeDown = IsInputKeyDown(EKeys::Escape);
	if (bEscapeDown && !bWasEscapeDown)
	{
		ToggleMenu();
	}
	bWasEscapeDown = bEscapeDown;

	if (bMenuOpen)
	{
		const bool bLeftMouseDown = IsInputKeyDown(EKeys::LeftMouseButton);
		if (bLeftMouseDown && !bWasLeftMouseDown)
		{
			HandleMenuClick();
		}
		bWasLeftMouseDown = bLeftMouseDown;
	}
	else
	{
		bWasLeftMouseDown = false;
	}
}

void AExtinctionPlayerController::ToggleMenu()
{
	SetMenuOpen(!bMenuOpen);
}

void AExtinctionPlayerController::SetMenuOpen(bool bOpen)
{
	bMenuOpen = bOpen;
	bShowMouseCursor = bMenuOpen;
	SetIgnoreLookInput(bMenuOpen);

	if (bMenuOpen)
	{
		FInputModeGameAndUI InputMode;
		InputMode.SetHideCursorDuringCapture(false);
		SetInputMode(InputMode);
	}
	else
	{
		FInputModeGameOnly InputMode;
		SetInputMode(InputMode);
	}
}

void AExtinctionPlayerController::HandleMenuClick()
{
	float MouseX = 0.0f;
	float MouseY = 0.0f;
	if (!GetMousePosition(MouseX, MouseY))
	{
		return;
	}

	const AExtinctionHud* ExtinctionHud = Cast<AExtinctionHud>(GetHUD());
	if (ExtinctionHud != nullptr && ExtinctionHud->IsQuitButtonHit(FVector2D(MouseX, MouseY)))
	{
		FPlatformMisc::RequestExit(false, TEXT("Extinction quit button"));
	}
}
