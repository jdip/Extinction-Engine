#include "ExtinctionAvatarPawn.h"

#include "Animation/AnimationAsset.h"
#include "Animation/AnimSingleNodeInstance.h"
#include "Camera/CameraComponent.h"
#include "Components/SceneComponent.h"
#include "Components/SkeletalMeshComponent.h"
#include "Components/SphereComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Engine/Engine.h"
#include "Engine/SkeletalMesh.h"
#include "Engine/StaticMesh.h"
#include "Engine/World.h"
#include "ExtinctionPlayerController.h"
#include "ExtinctionSocketClient.h"
#include "GameFramework/PlayerController.h"
#include "GameFramework/SpringArmComponent.h"
#include "HAL/PlatformMisc.h"
#include "InputCoreTypes.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "Materials/MaterialInterface.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "UObject/ConstructorHelpers.h"

namespace
{
constexpr double LocalAvatarCenterZ = 92.0;
constexpr double LocalAvatarMeshOffsetZ = -92.0;
constexpr float MaxClientFrameRate = 144.0f;
const FVector LocalMarkerLocation(0.0, 0.0, 70.0);
const FVector RemoteMarkerLocation(0.0, 0.0, 160.0);

bool ParseEndpoint(const FString& Endpoint, FString& OutHost, int32& OutPort)
{
	FString PortText;
	if (!Endpoint.Split(TEXT(":"), &OutHost, &PortText, ESearchCase::IgnoreCase, ESearchDir::FromEnd))
	{
		return false;
	}

	OutPort = FCString::Atoi(*PortText);
	return !OutHost.IsEmpty() && OutPort > 0;
}

int32 QuantizeMovementAxis(double Value)
{
	constexpr double DeadZone = 0.25;
	if (FMath::Abs(Value) < DeadZone)
	{
		return 0;
	}

	return Value > 0.0 ? 1 : -1;
}

void ConfigureAvatarMeshComponent(
	USkeletalMeshComponent* MeshComponent,
	USkeletalMesh* MeshAsset,
	const FVector& RelativeLocation)
{
	if (MeshComponent == nullptr)
	{
		return;
	}

	MeshComponent->SetSkeletalMesh(MeshAsset);
	MeshComponent->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	MeshComponent->SetRelativeLocation(RelativeLocation);
	MeshComponent->SetRelativeRotation(FRotator(0.0, -90.0, 0.0));
	MeshComponent->SetRelativeScale3D(FVector(1.0, 1.0, 1.0));
}

FLinearColor AvatarColorForPlayerId(uint64 PlayerId)
{
	static const FLinearColor Palette[] = {
		FLinearColor(0.95f, 0.20f, 0.16f),
		FLinearColor(0.12f, 0.55f, 1.00f),
		FLinearColor(0.22f, 0.85f, 0.38f),
		FLinearColor(1.00f, 0.76f, 0.18f),
		FLinearColor(0.78f, 0.32f, 1.00f),
		FLinearColor(0.10f, 0.90f, 0.84f),
		FLinearColor(1.00f, 0.42f, 0.70f),
		FLinearColor(0.80f, 0.95f, 0.24f),
	};

	const uint64 PaletteIndex = PlayerId == 0 ? 0 : (PlayerId - 1) % UE_ARRAY_COUNT(Palette);
	return Palette[PaletteIndex];
}

void ApplyColorParameters(UMaterialInstanceDynamic* Material, const FLinearColor& Color)
{
	if (Material == nullptr)
	{
		return;
	}

	Material->SetVectorParameterValue(TEXT("Color"), Color);
	Material->SetVectorParameterValue(TEXT("BaseColor"), Color);
	Material->SetVectorParameterValue(TEXT("Tint"), Color);
	Material->SetVectorParameterValue(TEXT("TintColor"), Color);
	Material->SetVectorParameterValue(TEXT("BodyColor"), Color);
}

void ApplyMeshColor(USkeletalMeshComponent* MeshComponent, uint64 PlayerId)
{
	if (MeshComponent == nullptr)
	{
		return;
	}

	const FLinearColor Color = AvatarColorForPlayerId(PlayerId);
	for (int32 MaterialIndex = 0; MaterialIndex < MeshComponent->GetNumMaterials(); ++MaterialIndex)
	{
		ApplyColorParameters(MeshComponent->CreateDynamicMaterialInstance(MaterialIndex), Color);
	}
}

void ConfigureMarkerComponent(
	UStaticMeshComponent* MarkerComponent,
	UStaticMesh* MarkerMesh,
	UMaterialInterface* MarkerMaterial,
	const FVector& RelativeLocation,
	uint64 PlayerId)
{
	if (MarkerComponent == nullptr)
	{
		return;
	}

	MarkerComponent->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	MarkerComponent->SetRelativeLocation(RelativeLocation);
	MarkerComponent->SetRelativeScale3D(FVector(0.18, 0.18, 0.18));
	if (MarkerMesh != nullptr)
	{
		MarkerComponent->SetStaticMesh(MarkerMesh);
	}
	if (MarkerMaterial != nullptr)
	{
		MarkerComponent->SetMaterial(0, MarkerMaterial);
	}

	const FLinearColor Color = AvatarColorForPlayerId(PlayerId);
	ApplyColorParameters(MarkerComponent->CreateDynamicMaterialInstance(0), Color);
}

void UpdateAvatarAnimation(
	USkeletalMeshComponent* MeshComponent,
	UAnimationAsset* IdleAnimation,
	UAnimationAsset* RunAnimation,
	bool bIsMoving)
{
	if (MeshComponent == nullptr)
	{
		return;
	}

	UAnimationAsset* DesiredAnimation = bIsMoving && RunAnimation != nullptr ? RunAnimation : IdleAnimation;
	if (DesiredAnimation == nullptr)
	{
		return;
	}

	MeshComponent->SetAnimationMode(EAnimationMode::AnimationSingleNode);
	UAnimSingleNodeInstance* SingleNodeInstance = MeshComponent->GetSingleNodeInstance();
	if (SingleNodeInstance == nullptr || SingleNodeInstance->GetAnimationAsset() != DesiredAnimation)
	{
		MeshComponent->SetAnimation(DesiredAnimation);
		MeshComponent->Play(true);
	}
}
}

AExtinctionAvatarPawn::AExtinctionAvatarPawn()
{
	PrimaryActorTick.bCanEverTick = true;
	AutoPossessPlayer = EAutoReceiveInput::Player0;

	Collision = CreateDefaultSubobject<USphereComponent>(TEXT("Collision"));
	Collision->InitSphereRadius(45.0f);
	SetRootComponent(Collision);

	VisualMesh = CreateDefaultSubobject<USkeletalMeshComponent>(TEXT("AvatarMesh"));
	VisualMesh->SetupAttachment(Collision);
	static ConstructorHelpers::FObjectFinder<USkeletalMesh> MannequinMesh(
		TEXT("/NetworkPredictionExtras/Animation/Characters/UE4_Guy/Mesh/SK_Mannequin.SK_Mannequin"));
	if (MannequinMesh.Succeeded())
	{
		AvatarMesh = MannequinMesh.Object;
		ConfigureAvatarMeshComponent(VisualMesh, AvatarMesh, FVector(0.0, 0.0, LocalAvatarMeshOffsetZ));
	}
	else
	{
		UE_LOG(LogTemp, Warning, TEXT("Extinction avatar mannequin mesh could not be loaded."));
	}

	static ConstructorHelpers::FObjectFinder<UAnimationAsset> IdleAnimationAsset(
		TEXT("/NetworkPredictionExtras/Animation/Characters/UE4_Guy/Animations/ThirdPersonIdle.ThirdPersonIdle"));
	if (IdleAnimationAsset.Succeeded())
	{
		IdleAnimation = IdleAnimationAsset.Object;
	}

	static ConstructorHelpers::FObjectFinder<UAnimationAsset> RunAnimationAsset(
		TEXT("/NetworkPredictionExtras/Animation/Characters/UE4_Guy/Animations/ThirdPersonRun.ThirdPersonRun"));
	if (RunAnimationAsset.Succeeded())
	{
		RunAnimation = RunAnimationAsset.Object;
	}

	ColorMarker = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("ColorMarker"));
	ColorMarker->SetupAttachment(Collision);
	static ConstructorHelpers::FObjectFinder<UStaticMesh> MarkerMeshAsset(
		TEXT("/Engine/BasicShapes/Sphere.Sphere"));
	if (MarkerMeshAsset.Succeeded())
	{
		MarkerMesh = MarkerMeshAsset.Object;
	}
	static ConstructorHelpers::FObjectFinder<UMaterialInterface> MarkerMaterialAsset(
		TEXT("/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));
	if (MarkerMaterialAsset.Succeeded())
	{
		MarkerMaterial = MarkerMaterialAsset.Object;
	}
	ConfigureMarkerComponent(ColorMarker, MarkerMesh, MarkerMaterial, LocalMarkerLocation, 0);
	UpdateAvatarAnimation(VisualMesh, IdleAnimation, RunAnimation, false);

	CameraBoom = CreateDefaultSubobject<USpringArmComponent>(TEXT("CameraBoom"));
	CameraBoom->SetupAttachment(Collision);
	CameraBoom->TargetArmLength = 320.0f;
	CameraBoom->SocketOffset = FVector(0.0, 55.0, 25.0);
	CameraBoom->SetRelativeLocation(FVector(0.0, 0.0, 85.0));
	CameraBoom->SetRelativeRotation(FRotator(CameraPitchDegrees, 0.0f, 0.0f));

	Camera = CreateDefaultSubobject<UCameraComponent>(TEXT("Camera"));
	Camera->SetupAttachment(CameraBoom);
}

void AExtinctionAvatarPawn::BeginPlay()
{
	Super::BeginPlay();
	if (GEngine != nullptr)
	{
		GEngine->SetMaxFPS(MaxClientFrameRate);
	}
	ApplyCommandLineSettings();
	CameraYawDegrees = GetActorRotation().Yaw;
	ApplyCameraRotation();
	SocketClient = MakeUnique<FExtinctionSocketClient>();
	AutoSmokeDeadlineSeconds = FPlatformTime::Seconds() + 15.0;
	TryConnectAndJoin();
}

void AExtinctionAvatarPawn::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);

	UpdateCameraFromMouse();
	TryConnectAndJoin();

	if (SocketClient.IsValid() && SocketClient->IsConnected())
	{
		TArray<FString> Lines;
		SocketClient->TickReceive(Lines);
		for (const FString& Line : Lines)
		{
			HandleServerLine(Line);
		}

		if (bAutoSmoke)
		{
			TickAutoSmoke();
		}
		else
		{
			SendMovementIntent();
		}
	}
	else if (bAutoSmoke)
	{
		TickAutoSmoke();
	}
}

void AExtinctionAvatarPawn::EndPlay(const EEndPlayReason::Type EndPlayReason)
{
	for (const TPair<uint64, TWeakObjectPtr<AActor>>& RemoteAvatar : RemoteAvatars)
	{
		if (AActor* RemoteActor = RemoteAvatar.Value.Get())
		{
			RemoteActor->Destroy();
		}
	}
	RemoteAvatars.Empty();

	if (SocketClient.IsValid())
	{
		SocketClient->Disconnect();
		SocketClient.Reset();
	}

	Super::EndPlay(EndPlayReason);
}

bool AExtinctionAvatarPawn::IsServerConnected() const
{
	return SocketClient.IsValid() && SocketClient->IsConnected();
}

FString AExtinctionAvatarPawn::GetServerEndpoint() const
{
	return FString::Printf(TEXT("%s:%d"), *ServerHost, ServerPort);
}

void AExtinctionAvatarPawn::ApplyCommandLineSettings()
{
	const TCHAR* CommandLine = FCommandLine::Get();

	FString ServerEndpoint;
	if (FParse::Value(CommandLine, TEXT("ExtinctionServer="), ServerEndpoint))
	{
		FString ParsedHost;
		int32 ParsedPort = 0;
		if (ParseEndpoint(ServerEndpoint, ParsedHost, ParsedPort))
		{
			ServerHost = ParsedHost;
			ServerPort = ParsedPort;
		}
		else
		{
			UE_LOG(LogTemp, Warning, TEXT("Invalid ExtinctionServer endpoint: %s"), *ServerEndpoint);
		}
	}

	FString HostOverride;
	if (FParse::Value(CommandLine, TEXT("ExtinctionHost="), HostOverride) && !HostOverride.IsEmpty())
	{
		ServerHost = HostOverride;
	}

	FString PortOverride;
	if (FParse::Value(CommandLine, TEXT("ExtinctionPort="), PortOverride))
	{
		const int32 ParsedPort = FCString::Atoi(*PortOverride);
		if (ParsedPort > 0)
		{
			ServerPort = ParsedPort;
		}
		else
		{
			UE_LOG(LogTemp, Warning, TEXT("Invalid ExtinctionPort value: %s"), *PortOverride);
		}
	}

	bAutoSmoke = FParse::Param(CommandLine, TEXT("ExtinctionAutoSmoke"));
	if (bAutoSmoke)
	{
		PlayerName = TEXT("unreal_auto_smoke");
		UE_LOG(LogTemp, Display, TEXT("Extinction auto smoke enabled for %s:%d"), *ServerHost, ServerPort);
	}
}

void AExtinctionAvatarPawn::ApplyCameraRotation()
{
	CameraYawDegrees = FRotator::NormalizeAxis(CameraYawDegrees);
	CameraPitchDegrees = FMath::Clamp(
		CameraPitchDegrees,
		MinimumCameraPitchDegrees,
		MaximumCameraPitchDegrees);

	SetActorRotation(FRotator(0.0, CameraYawDegrees, 0.0));
	CameraBoom->SetRelativeRotation(FRotator(CameraPitchDegrees, 0.0, 0.0));
}

void AExtinctionAvatarPawn::UpdateCameraFromMouse()
{
	if (bAutoSmoke || IsMenuOpen())
	{
		return;
	}

	const APlayerController* PlayerController = Cast<APlayerController>(GetController());
	if (PlayerController == nullptr)
	{
		return;
	}

	float MouseX = 0.0f;
	float MouseY = 0.0f;
	PlayerController->GetInputMouseDelta(MouseX, MouseY);
	if (FMath::IsNearlyZero(MouseX) && FMath::IsNearlyZero(MouseY))
	{
		return;
	}

	CameraYawDegrees += MouseX * MouseSensitivity;
	CameraPitchDegrees += MouseY * MouseSensitivity;
	ApplyCameraRotation();
}

void AExtinctionAvatarPawn::TryConnectAndJoin()
{
	if (!SocketClient.IsValid() || bJoinSent)
	{
		return;
	}

	FString Error;
	if (!SocketClient->IsConnected() && !SocketClient->Connect(ServerHost, ServerPort, Error))
	{
		UE_LOG(LogTemp, Warning, TEXT("Extinction client connect failed: %s"), *Error);
		return;
	}

	const FString JoinLine = FString::Printf(TEXT("join %s\n"), *PlayerName);
	if (!SocketClient->SendLine(JoinLine, Error))
	{
		UE_LOG(LogTemp, Warning, TEXT("Extinction client join failed: %s"), *Error);
		SocketClient->Disconnect();
		return;
	}

	bJoinSent = true;
	UE_LOG(LogTemp, Display, TEXT("Extinction client sent join to %s:%d"), *ServerHost, ServerPort);
}

void AExtinctionAvatarPawn::SendMovementIntent()
{
	if (PlayerId == 0)
	{
		return;
	}

	const APlayerController* PlayerController = Cast<APlayerController>(GetController());
	if (PlayerController == nullptr || IsMenuOpen())
	{
		return;
	}

	int32 ForwardInput = 0;
	int32 StrafeInput = 0;
	if (PlayerController->IsInputKeyDown(EKeys::D))
	{
		StrafeInput += 1;
	}
	if (PlayerController->IsInputKeyDown(EKeys::A))
	{
		StrafeInput -= 1;
	}
	if (PlayerController->IsInputKeyDown(EKeys::W))
	{
		ForwardInput += 1;
	}
	if (PlayerController->IsInputKeyDown(EKeys::S))
	{
		ForwardInput -= 1;
	}

	const double YawRadians = FMath::DegreesToRadians(static_cast<double>(CameraYawDegrees));
	const FVector2D Forward(FMath::Cos(YawRadians), FMath::Sin(YawRadians));
	const FVector2D Right(-FMath::Sin(YawRadians), FMath::Cos(YawRadians));
	const FVector2D WorldIntent = Forward * ForwardInput + Right * StrafeInput;

	const int32 XAxis = QuantizeMovementAxis(WorldIntent.X);
	const int32 YAxis = QuantizeMovementAxis(WorldIntent.Y);
	SendMovementCommand(XAxis, YAxis, CameraYawDegrees);
}

void AExtinctionAvatarPawn::SendMovementCommand(int32 XAxis, int32 YAxis, float FacingYawDegrees)
{
	if (!SocketClient.IsValid() || PlayerId == 0)
	{
		return;
	}

	const int32 QuantizedFacingYawDegrees =
		FMath::RoundToInt(FRotator::NormalizeAxis(FacingYawDegrees));
	const FString MoveLine = FString::Printf(
		TEXT("move %llu %d %d %d\n"),
		static_cast<unsigned long long>(PlayerId),
		XAxis,
		YAxis,
		QuantizedFacingYawDegrees);

	FString Error;
	if (!SocketClient->SendLine(MoveLine, Error))
	{
		UE_LOG(LogTemp, Warning, TEXT("Extinction client move failed: %s"), *Error);
	}
}

void AExtinctionAvatarPawn::TickAutoSmoke()
{
	if (bAutoSmokeCompleted)
	{
		return;
	}

	if (PlayerId != 0 && !bAutoSmokeMoveSent)
	{
		SendMovementCommand(1, 0, 0.0f);
		bAutoSmokeMoveSent = true;
		UE_LOG(LogTemp, Display, TEXT("Extinction auto smoke sent movement for player %llu"), PlayerId);
	}

	if (FPlatformTime::Seconds() > AutoSmokeDeadlineSeconds)
	{
		UE_LOG(LogTemp, Error, TEXT("Extinction auto smoke timed out before authoritative movement"));
		FinishAutoSmoke(1, TEXT("Extinction auto smoke timed out"));
	}
}

void AExtinctionAvatarPawn::FinishAutoSmoke(uint8 ExitCode, const TCHAR* Reason)
{
	if (bAutoSmokeCompleted)
	{
		return;
	}

	bAutoSmokeCompleted = true;
	FPlatformMisc::RequestExitWithStatus(false, ExitCode, Reason);
}

void AExtinctionAvatarPawn::HandleServerLine(const FString& Line)
{
	TArray<FString> Parts;
	Line.ParseIntoArrayWS(Parts);
	if (Parts.IsEmpty())
	{
		return;
	}

	if (Parts[0] == TEXT("joined"))
	{
		HandleJoinedLine(Parts);
	}
	else if (Parts[0] == TEXT("state"))
	{
		HandleStateLine(Parts);
	}
	else if (Parts[0] == TEXT("error"))
	{
		UE_LOG(LogTemp, Warning, TEXT("Extinction server error: %s"), *Line);
	}
}

void AExtinctionAvatarPawn::HandleJoinedLine(const TArray<FString>& Parts)
{
	if (Parts.Num() != 2)
	{
		return;
	}

	PlayerId = FCString::Strtoui64(*Parts[1], nullptr, 10);
	ApplyLocalAvatarPresentation();
	UE_LOG(LogTemp, Display, TEXT("Extinction client joined as player %llu"), PlayerId);
}

void AExtinctionAvatarPawn::HandleStateLine(const TArray<FString>& Parts)
{
	if (PlayerId == 0 || Parts.Num() < 4)
	{
		return;
	}

	const int32 AvatarCount = FCString::Atoi(*Parts[3]);
	const int32 ExpectedParts = 4 + AvatarCount * 6;
	if (Parts.Num() != ExpectedParts)
	{
		return;
	}

	LastServerTick = FCString::Strtoui64(*Parts[1], nullptr, 10);
	LastServerHash = Parts[2];
	LastAvatarCount = AvatarCount;

	bool bFoundLocalAvatar = false;
	TSet<uint64> SeenRemotePlayerIds;
	for (int32 Index = 4; Index < Parts.Num(); Index += 6)
	{
		const uint64 SnapshotPlayerId = FCString::Strtoui64(*Parts[Index], nullptr, 10);
		const int32 X = FCString::Atoi(*Parts[Index + 1]);
		const int32 Y = FCString::Atoi(*Parts[Index + 2]);
		const int32 Z = FCString::Atoi(*Parts[Index + 3]);
		const float FacingYawDegrees = static_cast<float>(FCString::Atoi(*Parts[Index + 4]));
		const bool bIsMoving = FCString::Atoi(*Parts[Index + 5]) != 0;
		const FVector AuthoritativePosition(
			static_cast<double>(X),
			static_cast<double>(Y),
			static_cast<double>(Z));

		if (SnapshotPlayerId == PlayerId)
		{
			bFoundLocalAvatar = true;
			LastAuthoritativePosition = AuthoritativePosition;
			LastAuthoritativeYawDegrees = FacingYawDegrees;
			bLastAuthoritativeMoving = bIsMoving;
			SetActorLocation(AuthoritativePosition + FVector(0.0, 0.0, LocalAvatarCenterZ));
			UpdateLocalAvatarAnimation(bIsMoving);
			if (bAutoSmoke && bAutoSmokeMoveSent && X > 0)
			{
				UE_LOG(
					LogTemp,
					Display,
					TEXT("Extinction auto smoke joined and moved player %llu to (%d, %d, %d)"),
					PlayerId,
					X,
					Y,
					Z);
				FinishAutoSmoke(0, TEXT("Extinction auto smoke succeeded"));
			}
		}
		else
		{
			SeenRemotePlayerIds.Add(SnapshotPlayerId);
			UpdateRemoteAvatar(SnapshotPlayerId, AuthoritativePosition, FacingYawDegrees, bIsMoving);
		}
	}

	PruneRemoteAvatars(SeenRemotePlayerIds);
	if (!bFoundLocalAvatar)
	{
		LastAuthoritativePosition = FVector::ZeroVector;
		LastAuthoritativeYawDegrees = 0.0f;
		bLastAuthoritativeMoving = false;
	}
}

void AExtinctionAvatarPawn::ApplyLocalAvatarPresentation()
{
	ApplyMeshColor(VisualMesh, PlayerId);
	ConfigureMarkerComponent(ColorMarker, MarkerMesh, MarkerMaterial, LocalMarkerLocation, PlayerId);
	UpdateLocalAvatarAnimation(bLastAuthoritativeMoving);
}

void AExtinctionAvatarPawn::UpdateLocalAvatarAnimation(bool bIsMoving)
{
	UpdateAvatarAnimation(VisualMesh, IdleAnimation, RunAnimation, bIsMoving);
}

void AExtinctionAvatarPawn::UpdateRemoteAvatar(
	uint64 SnapshotPlayerId,
	const FVector& GroundPosition,
	float FacingYawDegrees,
	bool bIsMoving)
{
	if (AvatarMesh == nullptr)
	{
		return;
	}

	UWorld* World = GetWorld();
	if (World == nullptr)
	{
		return;
	}

	AActor* RemoteActor = nullptr;
	if (TWeakObjectPtr<AActor>* ExistingActor = RemoteAvatars.Find(SnapshotPlayerId))
	{
		RemoteActor = ExistingActor->Get();
	}

	if (RemoteActor == nullptr)
	{
		FActorSpawnParameters SpawnParameters;
		RemoteActor = World->SpawnActor<AActor>(
			AActor::StaticClass(),
			GroundPosition,
			FRotator::ZeroRotator,
			SpawnParameters);
		if (RemoteActor == nullptr)
		{
			return;
		}

		USceneComponent* Root = NewObject<USceneComponent>(RemoteActor, TEXT("RemoteAvatarRoot"));
		Root->SetMobility(EComponentMobility::Movable);
		RemoteActor->SetRootComponent(Root);
		RemoteActor->AddInstanceComponent(Root);
		Root->RegisterComponent();

		USkeletalMeshComponent* RemoteMesh =
			NewObject<USkeletalMeshComponent>(RemoteActor, TEXT("RemoteAvatarMesh"));
		RemoteMesh->SetMobility(EComponentMobility::Movable);
		RemoteMesh->SetupAttachment(Root);
		ConfigureAvatarMeshComponent(RemoteMesh, AvatarMesh, FVector::ZeroVector);
		ApplyMeshColor(RemoteMesh, SnapshotPlayerId);
		UpdateAvatarAnimation(RemoteMesh, IdleAnimation, RunAnimation, bIsMoving);
		RemoteActor->AddInstanceComponent(RemoteMesh);
		RemoteMesh->RegisterComponent();

		UStaticMeshComponent* RemoteMarker =
			NewObject<UStaticMeshComponent>(RemoteActor, TEXT("RemoteColorMarker"));
		RemoteMarker->SetMobility(EComponentMobility::Movable);
		RemoteMarker->SetupAttachment(Root);
		ConfigureMarkerComponent(
			RemoteMarker,
			MarkerMesh,
			MarkerMaterial,
			RemoteMarkerLocation,
			SnapshotPlayerId);
		RemoteActor->AddInstanceComponent(RemoteMarker);
		RemoteMarker->RegisterComponent();

		RemoteAvatars.Add(SnapshotPlayerId, RemoteActor);
		UE_LOG(
			LogTemp,
			Display,
			TEXT("Extinction spawned remote avatar %llu"),
			static_cast<unsigned long long>(SnapshotPlayerId));
	}

	RemoteActor->SetActorLocation(GroundPosition);
	RemoteActor->SetActorRotation(FRotator(0.0, FacingYawDegrees, 0.0));
	if (USkeletalMeshComponent* RemoteMesh = RemoteActor->FindComponentByClass<USkeletalMeshComponent>())
	{
		UpdateAvatarAnimation(RemoteMesh, IdleAnimation, RunAnimation, bIsMoving);
	}
}

void AExtinctionAvatarPawn::PruneRemoteAvatars(const TSet<uint64>& SeenRemotePlayerIds)
{
	for (auto It = RemoteAvatars.CreateIterator(); It; ++It)
	{
		if (SeenRemotePlayerIds.Contains(It.Key()))
		{
			continue;
		}

		if (AActor* RemoteActor = It.Value().Get())
		{
			RemoteActor->Destroy();
		}
		It.RemoveCurrent();
	}
}

bool AExtinctionAvatarPawn::IsMenuOpen() const
{
	const AExtinctionPlayerController* ExtinctionController =
		Cast<AExtinctionPlayerController>(GetController());
	return ExtinctionController != nullptr && ExtinctionController->IsMenuOpen();
}
