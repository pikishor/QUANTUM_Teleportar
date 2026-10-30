#pragma once

#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "QTDrone.h"
#include "QTGameMode.generated.h"

class AQTCity;
class AQTCore;

// Owns the sector: spawns the city, patrols and cores, tracks the Observation level (heat) and score.
UCLASS()
class QUANTUMTELEPORTAR_API AQTGameMode : public AGameModeBase
{
    GENERATED_BODY()

public:
    AQTGameMode();

    virtual void BeginPlay() override;
    virtual void Tick(float Dt) override;
    virtual void HandleStartingNewPlayer_Implementation(APlayerController* NewPlayer) override;

    void AddHeat(float V) { Heat = FMath::Min(5.f, Heat + V); Quiet = 0.f; }
    void AddScore(float V) { Score += V; }
    void ShowMessage(const FString& Text, float Dur = 2.f) { Message = Text; MessageT = Dur; }
    void OnCoreCollected();
    void OnPlayerDied();

    AQTCity* GetCity() const { return City; }
    AQTDrone* SpawnDrone(EQTDroneType Type, const FVector& Loc, bool bAware, bool bReinforcement);

    float Heat = 0.f;
    float Score = 0.f;
    int32 CoresGot = 0;
    int32 CoresTotal = 6;
    FString Message;
    float MessageT = 0.f;
    TArray<TWeakObjectPtr<AQTCore>> Cores;

private:
    void SetupEnvironment();
    void SpawnPatrols();
    void SpawnCores(int32 Count);
    void SpawnReinforcement(const FVector& PlayerLoc);
    void RestartSector();

    UPROPERTY() AQTCity* City = nullptr;
    float Quiet = 0.f;
    float SpawnT = 0.f;
    FVector StartLocation = FVector(-3000.f, 400.f, 120.f);
};
