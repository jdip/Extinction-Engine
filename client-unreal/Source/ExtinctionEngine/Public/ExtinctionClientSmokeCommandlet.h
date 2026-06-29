#pragma once

#include "CoreMinimal.h"
#include "Commandlets/Commandlet.h"
#include "ExtinctionClientSmokeCommandlet.generated.h"

UCLASS()
class EXTINCTIONENGINE_API UExtinctionClientSmokeCommandlet : public UCommandlet
{
	GENERATED_BODY()

public:
	UExtinctionClientSmokeCommandlet();

	virtual int32 Main(const FString& Params) override;
};

