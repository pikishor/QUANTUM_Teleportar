#include "QTDrone.h"
#include "QTCharacter.h"
#include "QTCommon.h"
#include "QTGameMode.h"
#include "QTProjectile.h"
#include "QTQuantumComponent.h"
#include "Components/SphereComponent.h"
#include "Components/StaticMeshComponent.h"
#include "DrawDebugHelpers.h"
#include "Engine/World.h"
#include "EngineUtils.h"
#include "GameFramework/DamageType.h"
#include "Kismet/GameplayStatics.h"

FQTDroneSpec FQTDroneSpec::For(EQTDroneType Type)
{
    FQTDroneSpec S;
    switch (Type)
    {
    case EQTDroneType::Striker:
        S.Hp = 34.f; S.Speed = 1050.f; S.Range = 0.f; S.Damage = 30.f; S.Scale = 0.85f; S.Score = 40.f; S.Heat = 0.15f;
        S.bKamikaze = true; S.Color = FLinearColor(1.f, 0.63f, 0.23f);
        break;
    case EQTDroneType::Heavy:
        S.Hp = 230.f; S.Speed = 300.f; S.Range = 3000.f; S.FireMin = 1.5f; S.FireMax = 2.1f; S.Damage = 9.f; S.BoltSpeed = 2600.f;
        S.Burst = 3; S.Scale = 1.5f; S.Score = 160.f; S.Heat = 0.5f; S.Color = FLinearColor(0.7f, 0.36f, 1.f);
        break;
    default:
        break;   // Sentinel uses the struct defaults
    }
    return S;
}

AQTDrone::AQTDrone()
{
    PrimaryActorTick.bCanEverTick = true;

    Sphere = CreateDefaultSubobject<USphereComponent>(TEXT("Sphere"));
    Sphere->InitSphereRadius(95.f);
    Sphere->SetCollisionProfileName(TEXT("BlockAllDynamic"));   // blocks the Visibility channel so hitscan can hit it
    SetRootComponent(Sphere);

    UStaticMesh* CubeShape = QT::LoadShape(TEXT("/Engine/BasicShapes/Cube.Cube"));
    UStaticMesh* SphereShape = QT::LoadShape(TEXT("/Engine/BasicShapes/Sphere.Sphere"));
    UStaticMesh* CylinderShape = QT::LoadShape(TEXT("/Engine/BasicShapes/Cylinder.Cylinder"));
    auto Make = [this](const TCHAR* Name, UStaticMesh* Shape, const FVector& Loc, const FVector& Scale3D)
    {
        UStaticMeshComponent* C = CreateDefaultSubobject<UStaticMeshComponent>(Name);
        C->SetupAttachment(Sphere);
        C->SetCollisionEnabled(ECollisionEnabled::NoCollision);
        if (Shape) { C->SetStaticMesh(Shape); }
        C->SetRelativeLocation(Loc);
        C->SetRelativeScale3D(Scale3D);
        return C;
    };
    Hull = Make(TEXT("Hull"), CubeShape, FVector(0.f, 0.f, 0.f), FVector(0.95f, 0.95f, 0.6f));
    Eye = Make(TEXT("Eye"), SphereShape, FVector(55.f, 0.f, 5.f), FVector(0.3f, 0.3f, 0.3f));
    Ring = Make(TEXT("Ring"), CylinderShape, FVector(0.f, 0.f, -35.f), FVector(1.5f, 1.5f, 0.05f));
}

void AQTDrone::InitType(EQTDroneType InType, bool bStartAware)
{
    Type = InType;
    Spec = FQTDroneSpec::For(Type);
    Hp = MaxHp = Spec.Hp;
    bAware = bStartAware;
}

void AQTDrone::BeginPlay()
{
    Super::BeginPlay();
    SetActorScale3D(FVector(Spec.Scale));
    Home = GetActorLocation();
    FireT = FMath::FRandRange(0.5f, 1.5f);
    T = FMath::FRandRange(0.f, 10.f);
    QT::Tint(Hull, FLinearColor(0.1f, 0.1f, 0.14f));
    QT::Tint(Eye, Spec.Color);
    QT::Tint(Ring, Spec.Color);
}

float AQTDrone::TakeDamage(float Damage, FDamageEvent const& DamageEvent, AController* EventInstigator, AActor* DamageCauser)
{
    if (bDead) { return 0.f; }
    ApplyHit(Damage, false);
    return Damage;
}

void AQTDrone::ApplyHit(float Damage, bool bMirrored)
{
    if (bDead) { return; }
    Hp -= Damage;
    bAware = true;
    BarT = 3.f;
    if (!bMirrored)
    {
        for (TActorIterator<AQTDrone> It(GetWorld()); It; ++It)   // alert the patrol
        {
            if (*It != this && FVector::Dist2D(It->GetActorLocation(), GetActorLocation()) < 3500.f) { It->Alert(); }
        }
        if (AQTDrone* Partner = Linked.Get())
        {
            if (!Partner->IsDead())
            {
                Partner->ApplyHit(Damage, true);
                DrawDebugSphere(GetWorld(), Partner->GetActorLocation(), 180.f, 8, FColor(120, 250, 255), false, 0.2f, 0, 3.f);
            }
        }
    }
    if (Hp <= 0.f) { Die(); }
}

void AQTDrone::Die()
{
    if (bDead) { return; }
    bDead = true;
    UWorld* World = GetWorld();
    if (AQTGameMode* GM = World->GetAuthGameMode<AQTGameMode>())
    {
        GM->AddScore(Spec.Score);
        GM->AddHeat(Spec.Heat);
        GM->ShowMessage(FString::Printf(TEXT("DRONE DESTROYED  +%d"), FMath::RoundToInt(Spec.Score)), 1.f);
    }
    if (AQTCharacter* P = Cast<AQTCharacter>(UGameplayStatics::GetPlayerPawn(this, 0)))
    {
        P->Quantum->AddEnergy(8.f);
    }
    DrawDebugSphere(World, GetActorLocation(), 220.f * Spec.Scale, 12, Spec.Color.ToFColor(true), false, 0.35f, 0, 3.f);
    Destroy();
}

void AQTDrone::Fire(const FVector& Target)
{
    const FVector Muzzle = GetActorLocation() + GetActorForwardVector() * (70.f * Spec.Scale);
    const FVector Dir = FMath::VRandCone((Target - Muzzle).GetSafeNormal(), 0.04f);
    FActorSpawnParameters Params;
    Params.Owner = this;
    Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
    if (AQTProjectile* Bolt = GetWorld()->SpawnActor<AQTProjectile>(AQTProjectile::StaticClass(), Muzzle, Dir.Rotation(), Params))
    {
        Bolt->Launch(Dir, Spec.BoltSpeed, Spec.Damage, Spec.Color);
    }
}

void AQTDrone::Tick(float Dt)
{
    Super::Tick(Dt);
    if (bDead) { return; }
    UWorld* World = GetWorld();
    AQTCharacter* Player = Cast<AQTCharacter>(UGameplayStatics::GetPlayerPawn(this, 0));
    if (!Player) { return; }
    AQTGameMode* GM = World->GetAuthGameMode<AQTGameMode>();
    T += Dt;

    // target: the player, or the superposition decoy half the time
    RetargetT -= Dt;
    if (RetargetT <= 0.f)
    {
        RetargetT = FMath::FRandRange(0.6f, 1.4f);
        bTargetClone = Player->Quantum->HasClone() && FMath::FRand() < 0.5f;
    }
    AActor* Target = (bTargetClone && Player->Quantum->HasClone()) ? static_cast<AActor*>(Player->Quantum->GetClone()) : static_cast<AActor*>(Player);

    const FVector Me = GetActorLocation(), TPos = Target->GetActorLocation();
    FVector Flat = TPos - Me;
    Flat.Z = 0.f;
    const float Dist = static_cast<float>(Flat.Size());
    const FVector U = Dist > 1.f ? Flat / Dist : GetActorForwardVector();
    if (!bAware && (Dist < 3200.f || (GM && GM->Heat > 0.f && Dist < 8000.f))) { bAware = true; }

    FVector Move = FVector::ZeroVector;
    float Speed = 0.f;
    if (!bAware)
    {
        WanderT -= Dt;
        if (WanderT <= 0.f) { WanderT = FMath::FRandRange(2.f, 5.f); WanderYaw = FMath::FRandRange(0.f, 360.f); }
        FVector ToHome = Home - Me;
        ToHome.Z = 0.f;
        if (ToHome.Size() > 1400.f) { Move = ToHome.GetSafeNormal(); Speed = 250.f; }
        else { Move = FRotator(0.f, WanderYaw, 0.f).Vector(); Speed = 140.f; }
        SetActorRotation(FMath::RInterpTo(GetActorRotation(), Move.Rotation(), Dt, 3.f));
    }
    else
    {
        LosT -= Dt;
        if (LosT <= 0.f)
        {
            LosT = FMath::FRandRange(0.25f, 0.4f);
            FCollisionQueryParams Q(SCENE_QUERY_STAT(QTDroneLos), false, this);
            Q.AddIgnoredActor(Target);
            FHitResult H;
            bLos = Dist < 9000.f && !World->LineTraceSingleByChannel(H, Me, TPos, ECC_Visibility, Q);
        }
        SetActorRotation(FMath::RInterpTo(GetActorRotation(), U.Rotation(), Dt, 9.f));

        if (Spec.bKamikaze || Dist > Spec.Range * 0.95f || !bLos) { Move = U; Speed = Spec.Speed; }
        else if (Dist < Spec.Range * 0.45f) { Move = -U; Speed = Spec.Speed * 0.8f; }
        else
        {
            StrafeT -= Dt;
            if (StrafeT <= 0.f) { StrafeT = FMath::FRandRange(1.2f, 3.f); Strafe = -Strafe; }
            Move = FVector(-U.Y, U.X, 0.f) * Strafe;
            Speed = Spec.Speed * 0.6f;
        }

        if (Spec.bKamikaze && Dist < 250.f)
        {
            TArray<AActor*> Ignore;
            Ignore.Add(this);
            UGameplayStatics::ApplyRadialDamage(World, Spec.Damage, Me, 450.f, UDamageType::StaticClass(), Ignore, this, nullptr, true);
            Hp = 0.f;
            Die();
            return;
        }

        FireT -= Dt;
        if (!Spec.bKamikaze && bLos && Dist < Spec.Range * 1.15f && FireT <= 0.f)
        {
            FireT = FMath::FRandRange(Spec.FireMin, Spec.FireMax);
            BurstLeft = Spec.Burst;
            BurstT = 0.f;
        }
        if (BurstLeft > 0)
        {
            BurstT -= Dt;
            if (BurstT <= 0.f) { Fire(TPos); --BurstLeft; BurstT = 0.12f; }
        }
    }

    // keep drones from stacking on each other
    for (TActorIterator<AQTDrone> It(World); It; ++It)
    {
        if (*It == this || It->IsDead()) { continue; }
        FVector Away = Me - It->GetActorLocation();
        Away.Z = 0.f;
        const float D = static_cast<float>(Away.Size());
        if (D < 200.f && D > 1.f) { Move += (Away / D) * 0.8f; }
    }

    FVector NewLoc = Me + Move * Speed * Dt;
    NewLoc.Z = 90.f + FMath::Sin(T * 2.2f) * 12.f;
    SetActorLocation(NewLoc, true);

    if (BarT > 0.f)   // placeholder health bar until the UMG nameplate exists
    {
        BarT -= Dt;
        const FVector Base = GetActorLocation() + FVector(0.f, 0.f, 210.f * Spec.Scale);
        const FVector Side = Player->GetActorRightVector() * 70.f;
        DrawDebugLine(World, Base - Side, Base + Side, FColor(60, 10, 30), false, 0.f, 1, 8.f);
        DrawDebugLine(World, Base - Side, Base - Side + (Side * 2.f) * FMath::Clamp(Hp / MaxHp, 0.f, 1.f), FColor(255, 70, 100), false, 0.f, 2, 8.f);
    }
}
