#include "ExtinctionHud.h"

#include "Engine/Canvas.h"
#include "Engine/Engine.h"
#include "ExtinctionAvatarPawn.h"
#include "ExtinctionPlayerController.h"
#include "Misc/App.h"

namespace
{
constexpr float DiagnosticsX = 16.0f;
constexpr float DiagnosticsY = 16.0f;
constexpr float LineHeight = 18.0f;
constexpr float MenuWidth = 320.0f;
constexpr float MenuHeight = 180.0f;
constexpr float QuitButtonWidth = 180.0f;
constexpr float QuitButtonHeight = 44.0f;

FString BoolText(bool bValue)
{
	return bValue ? TEXT("connected") : TEXT("disconnected");
}
}

void AExtinctionHud::DrawHUD()
{
	Super::DrawHUD();

	DrawDiagnostics();

	const AExtinctionPlayerController* ExtinctionController =
		Cast<AExtinctionPlayerController>(PlayerOwner);
	if (ExtinctionController != nullptr && ExtinctionController->IsMenuOpen())
	{
		DrawEscMenu();
	}
	else
	{
		QuitButtonBounds = FBox2D(ForceInit);
	}
}

bool AExtinctionHud::IsQuitButtonHit(const FVector2D& ScreenPosition) const
{
	return QuitButtonBounds.bIsValid && QuitButtonBounds.IsInside(ScreenPosition);
}

void AExtinctionHud::DrawDiagnostics()
{
	const AExtinctionAvatarPawn* AvatarPawn = nullptr;
	if (PlayerOwner != nullptr)
	{
		AvatarPawn = Cast<AExtinctionAvatarPawn>(PlayerOwner->GetPawn());
	}

	const float DeltaSeconds = FMath::Max(FApp::GetDeltaTime(), KINDA_SMALL_NUMBER);
	const float Fps = 1.0f / DeltaSeconds;

	TArray<FString> Lines;
	Lines.Add(FString::Printf(TEXT("FPS: %.0f"), Fps));

	if (AvatarPawn != nullptr)
	{
		const FVector Position = AvatarPawn->GetLastAuthoritativePosition();
		Lines.Add(FString::Printf(TEXT("Server: %s (%s)"),
			*AvatarPawn->GetServerEndpoint(),
			*BoolText(AvatarPawn->IsServerConnected())));
		Lines.Add(FString::Printf(TEXT("Player: %llu"),
			static_cast<unsigned long long>(AvatarPawn->GetPlayerId())));
		Lines.Add(FString::Printf(TEXT("Server tick: %llu"),
			static_cast<unsigned long long>(AvatarPawn->GetLastServerTick())));
		Lines.Add(FString::Printf(TEXT("State hash: %s"), *AvatarPawn->GetLastServerHash()));
		Lines.Add(FString::Printf(TEXT("Avatars: %d"), AvatarPawn->GetLastAvatarCount()));
		Lines.Add(FString::Printf(TEXT("Position: %.0f, %.0f, %.0f"), Position.X, Position.Y, Position.Z));
		Lines.Add(FString::Printf(TEXT("Facing: %.0f (%s)"),
			AvatarPawn->GetLastAuthoritativeYawDegrees(),
			AvatarPawn->IsLastAuthoritativeMoving() ? TEXT("moving") : TEXT("idle")));
		Lines.Add(FString::Printf(TEXT("View: yaw %.0f / pitch %.0f"),
			AvatarPawn->GetCameraYawDegrees(),
			AvatarPawn->GetCameraPitchDegrees()));
	}
	else
	{
		Lines.Add(TEXT("Avatar: unavailable"));
	}

	const float PanelWidth = 360.0f;
	const float PanelHeight = 24.0f + Lines.Num() * LineHeight;
	DrawRect(FLinearColor(0.0f, 0.0f, 0.0f, 0.45f), 8.0f, 8.0f, PanelWidth, PanelHeight);

	for (int32 Index = 0; Index < Lines.Num(); ++Index)
	{
		DrawText(
			Lines[Index],
			FColor(176, 242, 204),
			DiagnosticsX,
			DiagnosticsY + Index * LineHeight,
			GEngine != nullptr ? GEngine->GetSmallFont() : nullptr,
			1.0f,
			false);
	}
}

void AExtinctionHud::DrawEscMenu()
{
	if (Canvas == nullptr)
	{
		return;
	}

	const float CenterX = Canvas->SizeX * 0.5f;
	const float CenterY = Canvas->SizeY * 0.5f;
	const float MenuX = CenterX - MenuWidth * 0.5f;
	const float MenuY = CenterY - MenuHeight * 0.5f;
	const float ButtonX = CenterX - QuitButtonWidth * 0.5f;
	const float ButtonY = MenuY + 100.0f;

	DrawRect(FLinearColor(0.0f, 0.0f, 0.0f, 0.78f), MenuX, MenuY, MenuWidth, MenuHeight);
	DrawText(
		TEXT("Paused"),
		FColor::White,
		MenuX + 24.0f,
		MenuY + 24.0f,
		GEngine != nullptr ? GEngine->GetMediumFont() : nullptr,
		1.0f,
		false);

	QuitButtonBounds = FBox2D(
		FVector2D(ButtonX, ButtonY),
		FVector2D(ButtonX + QuitButtonWidth, ButtonY + QuitButtonHeight));
	DrawRect(FLinearColor(0.13f, 0.35f, 0.28f, 1.0f), ButtonX, ButtonY, QuitButtonWidth, QuitButtonHeight);
	DrawText(
		TEXT("Quit"),
		FColor::White,
		ButtonX + 70.0f,
		ButtonY + 12.0f,
		GEngine != nullptr ? GEngine->GetSmallFont() : nullptr,
		1.0f,
		false);
}
