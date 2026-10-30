#include "QTGameMode.h"
#include "QTCharacter.h"
#include "QTCity.h"
#include "QTCommon.h"
#include "QTCore.h"
#include "QTHUD.h"
#include "QTPlayerController.h"
#include "Components/DirectionalLightComponent.h"
#include "Components/ExponentialHeightFogComponent.h"
#include "Components/SkyLightComponent.h"
#include "Engine/DirectionalLight.h"
#include "Engine/ExponentialHeightFog.h"
#include "Engine/SkyLight.h"
#include "Engine/World.h"
#include "EngineUtils.h"
#include "Kismet/GameplayStatics.h"
#include "TimerManager.h"

AQTGameMode::AQTGameMode()
{
    PrimaryActorTick.bCanEverTick = true;
    DefaultPawnClass = AQTCharacter::StaticClass();
    PlayerControllerClass = AQTPlayerController::StaticClass();
    HUDClass = AQTHUD::StaticClass();
}

void AQTGameMode::HandleStartingNewPlayer_Implementation(APlayerController* NewPlayer)
{
    Super::HandleStartingNewPlayer_Implementation(NewPlayer);
    if (APawn* Pawn = NewPlayer ? NewPlayer->GetPawn() : nullptr)
    {
        Pawn->TeleportTo(StartLocation, FRotator::ZeroRotator);
        NewPlayer->SetControlRotation(FRotator::ZeroRotator);
    }
}

void AQTGameMode::BeginPlay()
{
    Super::BeginPlay();
    SetupEnvironment();
    City = GetWorld()->SpawnActor<AQTCity>(AQTCity::StaticClass(), FTransform::Identity);
    SpawnPatrols();
    SpawnCores(CoresTotal);
    ShowMessage(TEXT("RECOVER THE QUANTUM CORES - FOLLOW THE MAGENTA BEAMS"), 4.f);
}

// Only adds lighting when the level has none, so a real level can bring its own.
void AQTGameMode::SetupEnvironment()
{
    UWorld* World = GetWorld();
    TActorIterator<ADirectionalLight> ExistingSun(World);
    if (ExistingSun)
    {
        return;
    }
    if (ADirectionalLight* Sun = World->SpawnActor<ADirectionalLight>(FVector(0.f, 0.f, 5000.f), FRotator(-45.f, 30.f, 0.f)))
    {
        Sun->GetRootComponent()->SetMobility(EComponentMobility::Movable);
        Sun->GetLightComponent()->SetIntensity(6.f);
        Sun->GetLightComponent()->SetLightColor(FLinearColor(0.65f, 0.8f, 1.f));
    }
    if (ASkyLight* Sky = World->SpawnActor<ASkyLight>(FVector(0.f, 0.f, 6000.f), FRotator::ZeroRotator))
    {
        Sky->GetRootComponent()->SetMobility(EComponentMobility::Movable);
        Sky->GetLightComponent()->SetIntensity(1.f);
        Sky->GetLightComponent()->SetLightColor(FLinearColor(0.5f, 0.4f, 1.f));
        Sky->GetLightComponent()->RecaptureSky();
    }
    if (AExponentialHeightFog* Fog = World->SpawnActor<AExponentialHeightFog>(FVector(0.f, 0.f, 0.f), FRotator::ZeroRotator))
    {
        Fog->GetComponent()->SetFogDensity(0.004f);
        Fog->GetComponent()->SetFogInscatteringColor(FLinearColor(0.2f, 0.08f, 0.4f));
    }
}

AQTDrone* AQTGameMode::SpawnDrone(EQTDroneType Type, const FVector& Loc, bool bAware, bool bReinforcement)
{
    const FTransform Xf(FRotator::ZeroRotator, Loc);
    AQTDrone* Drone = GetWorld()->SpawnActorDeferred<AQTDrone>(AQTDrone::StaticClass(), Xf, nullptr, nullptr, ESpawnActorCollisionHandlingMethod::AlwaysSpawn);
    if (!Drone)
    {
        return nullptr;
    }
    Drone->InitType(Type, bAware);
    Drone->bReinforcement = bReinforcement;
    Drone->FinishSpawning(Xf);
    return Drone;
}

void AQTGameMode::SpawnPatrols()
{
    for (int32 G = 0; G < 7; ++G)
    {
        FVector P;
        int32 Guard = 0;
        do { P = City->RandomRoadPoint(); } while (FVector::Dist2D(P, StartLocation) < 11000.f && ++Guard < 50);
        const bool bFar = FVector2D(P.X, P.Y).Size() > 20000.f;
        for (int32 i = 0; i < 2 + (G % 2); ++i)
        {
            const EQTDroneType Type = (bFar && i == 0 && G % 3 == 0) ? EQTDroneType::Heavy : EQTDroneType::Sentinel;
            SpawnDrone(Type, FVector(P.X + FMath::FRandRange(-400.f, 400.f), P.Y + FMath::FRandRange(-400.f, 400.f), 90.f), false, false);
        }
    }
}

void AQTGameMode::SpawnCores(int32 Count)
{
    Cores.Reset();
    CoresGot = 0;
    TArray<FVector> Spots = City->Intersections;
    for (int32 i = Spots.Num() - 1; i > 0; --i)   // shuffle
    {
        Spots.Swap(i, FMath::RandRange(0, i));
    }
    TArray<FVector> Chosen;
    for (const FVector& S : Spots)
    {
        if (Chosen.Num() >= Count) { break; }
        if (FVector::Dist2D(S, StartLocation) < 14000.f) { continue; }
        bool bFarEnough = true;
        for (const FVector& C : Chosen)
        {
            if (FVector::Dist2D(S, C) < 11000.f) { bFarEnough = false; break; }
        }
        if (bFarEnough) { Chosen.Add(S); }
    }
    for (const FVector& S : Chosen)
    {
        if (AQTCore* Core = GetWorld()->SpawnActor<AQTCore>(AQTCore::StaticClass(), FTransform(FRotator::ZeroRotator, S + FVector(0.f, 0.f, 100.f))))
        {
            Cores.Add(Core);
        }
    }
    CoresTotal = Cores.Num();
}

void AQTGameMode::SpawnReinforcement(const FVector& PlayerLoc)
{
    FVector P;
    if (!City->RoadPointNear(PlayerLoc, 3800.f, 7500.f, P))
    {
        return;
    }
    const float R = FMath::FRand();
    const EQTDroneType Type = (Heat >= 3.f && R < 0.25f) ? EQTDroneType::Heavy : (R < 0.35f ? EQTDroneType::Striker : EQTDroneType::Sentinel);
    SpawnDrone(Type, FVector(P.X, P.Y, 90.f), true, true);
}

void AQTGameMode::Tick(float Dt)
{
    Super::Tick(Dt);
    MessageT = FMath::Max(0.f, MessageT - Dt);
    const AQTCharacter* Player = Cast<AQTCharacter>(UGameplayStatics::GetPlayerPawn(this, 0));
    if (!Player || !City) { return; }

    // The Observation level decays once nothing is hunting the player.
    bool bAwareNearby = false;
    int32 Near = 0;
    for (TActorIterator<AQTDrone> It(GetWorld()); It; ++It)
    {
        if (It->IsDead()) { continue; }
        const double Dist = FVector::Dist2D(It->GetActorLocation(), Player->GetActorLocation());
        if (Dist < 11000.0) { ++Near; }
        if (It->IsAware() && Dist < 7000.0) { bAwareNearby = true; }
    }
    Quiet = bAwareNearby ? 0.f : Quiet + Dt;
    if (Quiet > 7.f && Heat > 0.f) { Heat = FMath::Max(0.f, Heat - 0.12f * Dt); }

    SpawnT -= Dt;
    const int32 Want = Heat >= 1.f ? FMath::FloorToInt(2.f + Heat * 2.6f) : 0;
    if (SpawnT <= 0.f && Want > 0 && Near < Want)
    {
        SpawnT = 1.4f;
        SpawnReinforcement(Player->GetActorLocation());
    }
}

void AQTGameMode::OnCoreCollected()
{
    ++CoresGot;
    Score += 250.f;
    if (CoresGot >= CoresTotal)
    {
        ShowMessage(TEXT("SECTOR STABILIZED"), 4.f);
        FTimerHandle Handle;
        GetWorldTimerManager().SetTimer(Handle, this, &AQTGameMode::RestartSector, 4.f, false);
    }
    else
    {
        ShowMessage(FString::Printf(TEXT("QUANTUM CORE RECOVERED  %d/%d"), CoresGot, CoresTotal), 2.f);
    }
}

void AQTGameMode::RestartSector()
{
    Heat = 0.f;
    SpawnCores(FMath::Min(9, CoresTotal + 1));
    ShowMessage(TEXT("NEW SECTOR - MORE CORES, MORE OBSERVERS"), 3.f);
}

void AQTGameMode::OnPlayerDied()
{
    ShowMessage(TEXT("DECOHERED - YOU WERE OBSERVED"), 3.f);
    FTimerHandle Handle;
    FTimerDelegate Restart = FTimerDelegate::CreateLambda([this]()
    {
        UGameplayStatics::OpenLevel(this, FName(*UGameplayStatics::GetCurrentLevelName(this)));
    });
    GetWorldTimerManager().SetTimer(Handle, Restart, 3.f, false);
}
