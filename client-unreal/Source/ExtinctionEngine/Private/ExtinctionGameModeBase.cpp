#include "ExtinctionGameModeBase.h"

#include "Components/StaticMeshComponent.h"
#include "Engine/StaticMeshActor.h"
#include "ExtinctionAvatarPawn.h"
#include "ExtinctionHud.h"
#include "ExtinctionPlayerController.h"

AExtinctionGameModeBase::AExtinctionGameModeBase()
{
	DefaultPawnClass = AExtinctionAvatarPawn::StaticClass();
	PlayerControllerClass = AExtinctionPlayerController::StaticClass();
	HUDClass = AExtinctionHud::StaticClass();
}

void AExtinctionGameModeBase::StartPlay()
{
	Super::StartPlay();
	SpawnDebugFloor();
}

void AExtinctionGameModeBase::SpawnDebugFloor()
{
	UWorld* World = GetWorld();
	if (World == nullptr)
	{
		return;
	}

	UStaticMesh* PlaneMesh = LoadObject<UStaticMesh>(nullptr, TEXT("/Engine/BasicShapes/Plane.Plane"));
	if (PlaneMesh == nullptr)
	{
		return;
	}

	AStaticMeshActor* Floor = World->SpawnActor<AStaticMeshActor>();
	if (Floor == nullptr)
	{
		return;
	}

	Floor->GetStaticMeshComponent()->SetMobility(EComponentMobility::Movable);
	Floor->GetStaticMeshComponent()->SetStaticMesh(PlaneMesh);
	Floor->SetActorScale3D(FVector(50.0, 50.0, 1.0));
	Floor->SetActorLocation(FVector::ZeroVector);
}
