#include "ExtinctionClientSmokeCommandlet.h"

#include "ExtinctionSocketClient.h"

namespace
{
bool ParseServerEndpoint(const FString& Params, FString& OutHost, int32& OutPort)
{
	FString Server = TEXT("127.0.0.1:7007");
	FParse::Value(*Params, TEXT("Server="), Server);

	FString PortText;
	if (!Server.Split(TEXT(":"), &OutHost, &PortText, ESearchCase::IgnoreCase, ESearchDir::FromEnd))
	{
		return false;
	}

	OutPort = FCString::Atoi(*PortText);
	return !OutHost.IsEmpty() && OutPort > 0;
}

bool ReadUntilJoined(FExtinctionSocketClient& Client, uint64& OutPlayerId)
{
	FString Error;
	for (int32 Attempt = 0; Attempt < 200; ++Attempt)
	{
		FString Line;
		if (!Client.ReadLineBlocking(Line, 0.05, Error))
		{
			continue;
		}

		TArray<FString> Parts;
		Line.ParseIntoArrayWS(Parts);
		if (Parts.Num() == 2 && Parts[0] == TEXT("joined"))
		{
			OutPlayerId = FCString::Strtoui64(*Parts[1], nullptr, 10);
			return OutPlayerId > 0;
		}
	}

	return false;
}

bool ReadUntilMoved(FExtinctionSocketClient& Client, uint64 PlayerId)
{
	FString Error;
	for (int32 Attempt = 0; Attempt < 200; ++Attempt)
	{
		FString Line;
		if (!Client.ReadLineBlocking(Line, 0.05, Error))
		{
			continue;
		}

		TArray<FString> Parts;
		Line.ParseIntoArrayWS(Parts);
		if (Parts.Num() < 8 || Parts[0] != TEXT("state"))
		{
			continue;
		}

		const int32 AvatarCount = FCString::Atoi(*Parts[3]);
		if (Parts.Num() != 4 + AvatarCount * 6)
		{
			continue;
		}

		for (int32 Index = 4; Index < Parts.Num(); Index += 6)
		{
			const uint64 SnapshotPlayerId = FCString::Strtoui64(*Parts[Index], nullptr, 10);
			const int32 X = FCString::Atoi(*Parts[Index + 1]);
			if (SnapshotPlayerId == PlayerId && X > 0)
			{
				return true;
			}
		}
	}

	return false;
}
}

UExtinctionClientSmokeCommandlet::UExtinctionClientSmokeCommandlet()
{
	IsClient = false;
	IsEditor = false;
	IsServer = false;
	LogToConsole = true;
}

int32 UExtinctionClientSmokeCommandlet::Main(const FString& Params)
{
	FString Host;
	int32 Port = 0;
	if (!ParseServerEndpoint(Params, Host, Port))
	{
		UE_LOG(LogTemp, Error, TEXT("Invalid Server parameter. Use -Server=127.0.0.1:7007"));
		return 2;
	}

	FExtinctionSocketClient Client;
	FString Error;
	if (!Client.Connect(Host, Port, Error))
	{
		UE_LOG(LogTemp, Error, TEXT("Could not connect to dino_server: %s"), *Error);
		return 1;
	}

	if (!Client.SendLine(TEXT("join unreal_smoke\n"), Error))
	{
		UE_LOG(LogTemp, Error, TEXT("Could not send join: %s"), *Error);
		return 1;
	}

	uint64 PlayerId = 0;
	if (!ReadUntilJoined(Client, PlayerId))
	{
		UE_LOG(LogTemp, Error, TEXT("Did not receive joined response"));
		return 1;
	}

	const FString MoveLine = FString::Printf(
		TEXT("move %llu 1 0 0\n"),
		static_cast<unsigned long long>(PlayerId));
	if (!Client.SendLine(MoveLine, Error))
	{
		UE_LOG(LogTemp, Error, TEXT("Could not send movement: %s"), *Error);
		return 1;
	}

	if (!ReadUntilMoved(Client, PlayerId))
	{
		UE_LOG(LogTemp, Error, TEXT("Did not receive moved authoritative state"));
		return 1;
	}

	UE_LOG(LogTemp, Display, TEXT("Extinction Unreal smoke client joined and moved as player %llu"), PlayerId);
	return 0;
}
