#pragma once

#include "CoreMinimal.h"
#include "ExtinctionSocketClient.h"
#include "GameFramework/Pawn.h"
#include "Templates/UniquePtr.h"
#include "ExtinctionAvatarPawn.generated.h"

class AActor;
class UAnimationAsset;
class UCameraComponent;
class UMaterialInterface;
class USkeletalMesh;
class USkeletalMeshComponent;
class USphereComponent;
class UStaticMesh;
class UStaticMeshComponent;
class USpringArmComponent;

UCLASS()
class EXTINCTIONENGINE_API AExtinctionAvatarPawn : public APawn
{
	GENERATED_BODY()

public:
	AExtinctionAvatarPawn();

	virtual void BeginPlay() override;
	virtual void Tick(float DeltaSeconds) override;
	virtual void EndPlay(const EEndPlayReason::Type EndPlayReason) override;

	bool IsServerConnected() const;
	uint64 GetPlayerId() const { return PlayerId; }
	uint64 GetLastServerTick() const { return LastServerTick; }
	const FString& GetLastServerHash() const { return LastServerHash; }
	int32 GetLastAvatarCount() const { return LastAvatarCount; }
	FVector GetLastAuthoritativePosition() const { return LastAuthoritativePosition; }
	float GetLastAuthoritativeYawDegrees() const { return LastAuthoritativeYawDegrees; }
	bool IsLastAuthoritativeMoving() const { return bLastAuthoritativeMoving; }
	float GetCameraYawDegrees() const { return CameraYawDegrees; }
	float GetCameraPitchDegrees() const { return CameraPitchDegrees; }
	FString GetServerEndpoint() const;

private:
	UPROPERTY(VisibleAnywhere, Category = "Extinction")
	TObjectPtr<USphereComponent> Collision;

	UPROPERTY(VisibleAnywhere, Category = "Extinction")
	TObjectPtr<USkeletalMeshComponent> VisualMesh;

	UPROPERTY(VisibleAnywhere, Category = "Extinction")
	TObjectPtr<UStaticMeshComponent> ColorMarker;

	UPROPERTY(VisibleAnywhere, Category = "Extinction")
	TObjectPtr<USpringArmComponent> CameraBoom;

	UPROPERTY(VisibleAnywhere, Category = "Extinction")
	TObjectPtr<UCameraComponent> Camera;

	UPROPERTY(EditAnywhere, Category = "Extinction Network")
	FString ServerHost = TEXT("127.0.0.1");

	UPROPERTY(EditAnywhere, Category = "Extinction Network")
	int32 ServerPort = 7007;

	UPROPERTY(EditAnywhere, Category = "Extinction Network")
	FString PlayerName = TEXT("unreal_avatar");

	UPROPERTY(EditAnywhere, Category = "Extinction Camera")
	float MouseSensitivity = 0.45f;

	UPROPERTY(EditAnywhere, Category = "Extinction Camera")
	float MinimumCameraPitchDegrees = -55.0f;

	UPROPERTY(EditAnywhere, Category = "Extinction Camera")
	float MaximumCameraPitchDegrees = 35.0f;

	TUniquePtr<FExtinctionSocketClient> SocketClient;
	uint64 PlayerId = 0;
	uint64 LastServerTick = 0;
	FString LastServerHash = TEXT("-");
	int32 LastAvatarCount = 0;
	FVector LastAuthoritativePosition = FVector::ZeroVector;
	float LastAuthoritativeYawDegrees = 0.0f;
	bool bLastAuthoritativeMoving = false;
	float CameraYawDegrees = 0.0f;
	float CameraPitchDegrees = -8.0f;
	bool bJoinSent = false;
	bool bAutoSmoke = false;
	bool bAutoSmokeMoveSent = false;
	bool bAutoSmokeCompleted = false;
	double AutoSmokeDeadlineSeconds = 0.0;

	UPROPERTY()
	TObjectPtr<USkeletalMesh> AvatarMesh;

	UPROPERTY()
	TObjectPtr<UAnimationAsset> IdleAnimation;

	UPROPERTY()
	TObjectPtr<UAnimationAsset> RunAnimation;

	UPROPERTY()
	TObjectPtr<UStaticMesh> MarkerMesh;

	UPROPERTY()
	TObjectPtr<UMaterialInterface> MarkerMaterial;

	TMap<uint64, TWeakObjectPtr<AActor>> RemoteAvatars;

	void ApplyCommandLineSettings();
	void ApplyCameraRotation();
	void UpdateCameraFromMouse();
	void TryConnectAndJoin();
	void SendMovementIntent();
	void SendMovementCommand(int32 XAxis, int32 YAxis, float FacingYawDegrees);
	void TickAutoSmoke();
	void FinishAutoSmoke(uint8 ExitCode, const TCHAR* Reason);
	void HandleServerLine(const FString& Line);
	void HandleJoinedLine(const TArray<FString>& Parts);
	void HandleStateLine(const TArray<FString>& Parts);
	void ApplyLocalAvatarPresentation();
	void UpdateLocalAvatarAnimation(bool bIsMoving);
	void UpdateRemoteAvatar(
		uint64 SnapshotPlayerId,
		const FVector& GroundPosition,
		float FacingYawDegrees,
		bool bIsMoving);
	void PruneRemoteAvatars(const TSet<uint64>& SeenRemotePlayerIds);
	bool IsMenuOpen() const;
};
