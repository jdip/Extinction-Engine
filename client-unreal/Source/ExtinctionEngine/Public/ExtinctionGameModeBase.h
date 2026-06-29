#pragma once

#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "ExtinctionGameModeBase.generated.h"

UCLASS()
class EXTINCTIONENGINE_API AExtinctionGameModeBase : public AGameModeBase
{
	GENERATED_BODY()

public:
	AExtinctionGameModeBase();

	virtual void StartPlay() override;

private:
	void SpawnDebugFloor();
};

