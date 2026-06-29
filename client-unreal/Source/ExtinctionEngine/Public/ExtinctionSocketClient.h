#pragma once

#include "CoreMinimal.h"

class FSocket;

class EXTINCTIONENGINE_API FExtinctionSocketClient
{
public:
	FExtinctionSocketClient() = default;
	~FExtinctionSocketClient();

	bool Connect(const FString& Host, int32 Port, FString& OutError);
	void Disconnect();
	bool IsConnected() const;

	bool SendLine(const FString& Line, FString& OutError);
	void TickReceive(TArray<FString>& OutLines);
	bool ReadLineBlocking(FString& OutLine, double TimeoutSeconds, FString& OutError);

private:
	void ExtractLines(TArray<FString>& OutLines);

	FSocket* Socket = nullptr;
	FString PendingText;
	bool bConnected = false;
};
