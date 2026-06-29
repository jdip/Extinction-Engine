#include "ExtinctionSocketClient.h"

#include "IPAddress.h"
#include "SocketSubsystem.h"
#include "Sockets.h"

FExtinctionSocketClient::~FExtinctionSocketClient()
{
	Disconnect();
}

bool FExtinctionSocketClient::Connect(const FString& Host, int32 Port, FString& OutError)
{
	Disconnect();

	ISocketSubsystem* SocketSubsystem = ISocketSubsystem::Get(PLATFORM_SOCKETSUBSYSTEM);
	if (SocketSubsystem == nullptr)
	{
		OutError = TEXT("socket subsystem is unavailable");
		return false;
	}

	TSharedRef<FInternetAddr> ServerAddr = SocketSubsystem->CreateInternetAddr();
	bool bIsValidAddress = false;
	ServerAddr->SetIp(*Host, bIsValidAddress);
	ServerAddr->SetPort(Port);
	if (!bIsValidAddress)
	{
		OutError = FString::Printf(TEXT("invalid server host: %s"), *Host);
		return false;
	}

	Socket = SocketSubsystem->CreateSocket(NAME_Stream, TEXT("ExtinctionSocketClient"), false);
	if (Socket == nullptr)
	{
		OutError = TEXT("could not create TCP socket");
		return false;
	}

	Socket->SetNonBlocking(false);
	if (!Socket->Connect(*ServerAddr))
	{
		OutError = FString::Printf(TEXT("could not connect to %s:%d"), *Host, Port);
		Disconnect();
		return false;
	}

	Socket->SetNonBlocking(true);
	bConnected = true;
	return true;
}

void FExtinctionSocketClient::Disconnect()
{
	if (Socket == nullptr)
	{
		return;
	}

	ISocketSubsystem* SocketSubsystem = ISocketSubsystem::Get(PLATFORM_SOCKETSUBSYSTEM);
	Socket->Close();
	if (SocketSubsystem != nullptr)
	{
		SocketSubsystem->DestroySocket(Socket);
	}
	Socket = nullptr;
	PendingText.Empty();
	bConnected = false;
}

bool FExtinctionSocketClient::IsConnected() const
{
	return Socket != nullptr && bConnected && Socket->GetConnectionState() != SCS_ConnectionError;
}

bool FExtinctionSocketClient::SendLine(const FString& Line, FString& OutError)
{
	if (!IsConnected())
	{
		OutError = TEXT("socket is not connected");
		return false;
	}

	FTCHARToUTF8 Converter(*Line);
	int32 BytesSent = 0;
	const bool bSent = Socket->Send(
		reinterpret_cast<const uint8*>(Converter.Get()),
		Converter.Length(),
		BytesSent);
	if (!bSent || BytesSent != Converter.Length())
	{
		OutError = TEXT("failed to send complete line");
		return false;
	}

	return true;
}

void FExtinctionSocketClient::TickReceive(TArray<FString>& OutLines)
{
	if (Socket == nullptr)
	{
		return;
	}

	uint32 PendingDataSize = 0;
	while (Socket->HasPendingData(PendingDataSize))
	{
		const uint32 ReadSize = FMath::Min(PendingDataSize, static_cast<uint32>(4096));
		TArray<uint8> Buffer;
		Buffer.SetNumUninitialized(static_cast<int32>(ReadSize) + 1);

		int32 BytesRead = 0;
		if (!Socket->Recv(Buffer.GetData(), static_cast<int32>(ReadSize), BytesRead) || BytesRead <= 0)
		{
			return;
		}

		Buffer[BytesRead] = 0;
		PendingText += FString(UTF8_TO_TCHAR(reinterpret_cast<const char*>(Buffer.GetData())));
	}

	ExtractLines(OutLines);
}

bool FExtinctionSocketClient::ReadLineBlocking(
	FString& OutLine,
	double TimeoutSeconds,
	FString& OutError)
{
	const double Deadline = FPlatformTime::Seconds() + TimeoutSeconds;
	while (FPlatformTime::Seconds() < Deadline)
	{
		TArray<FString> Lines;
		TickReceive(Lines);
		if (!Lines.IsEmpty())
		{
			OutLine = Lines[0];
			return true;
		}

		FPlatformProcess::Sleep(0.01f);
	}

	OutError = TEXT("timed out waiting for server line");
	return false;
}

void FExtinctionSocketClient::ExtractLines(TArray<FString>& OutLines)
{
	int32 NewlineIndex = INDEX_NONE;
	while (PendingText.FindChar(TEXT('\n'), NewlineIndex))
	{
		FString Line = PendingText.Left(NewlineIndex).TrimStartAndEnd();
		PendingText.RightChopInline(NewlineIndex + 1, EAllowShrinking::No);
		if (!Line.IsEmpty())
		{
			OutLines.Add(MoveTemp(Line));
		}
	}
}
