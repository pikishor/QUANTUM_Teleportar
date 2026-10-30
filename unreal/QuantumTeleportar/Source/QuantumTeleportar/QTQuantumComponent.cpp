#include "QTQuantumComponent.h"
#include "QTCharacter.h"
#include "QTCommon.h"
#include "QTDrone.h"
#include "QTGameMode.h"
#include "Components/CapsuleComponent.h"
#include "Components/SphereComponent.h"
#include "Components/StaticMeshComponent.h"
#include "DrawDebugHelpers.h"
#include "Engine/World.h"
#include "EngineUtils.h"
#include "GameFramework/DamageType.h"
#include "GameFramework/PlayerController.h"
#include "Kismet/GameplayStatics.h"

// ---- AQTClone -----------------------------------------------------------------------------------

AQTClone::AQTClone()
{
    PrimaryActorTick.bCanEverTick = false;
    Sphere = CreateDefaultSubobject<USphereComponent>(TEXT("Sphere"));
    Sphere->InitSphereRadius(70.f);
    Sphere->SetCollisionProfileName(TEXT("OverlapAllDynamic"));
    SetRootComponent(Sphere);

    Body = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("Body"));
    Body->SetupAttachment(Sphere);
    Body->SetCollisionEnabled(ECollisionEnabled::NoCollision);
    if (UStaticMesh* Shape = QT::LoadShape(TEXT("/Engine/BasicShapes/Cylinder.Cylinder")))
    {
        Body->SetStaticMesh(Shape);
    }
    Body->SetRelativeScale3D(FVector(0.55f, 0.55f, 1.7f));
}

void AQTClone::BeginPlay()
{
    Super::BeginPlay();
    QT::Tint(Body, FLinearColor(0.3f, 1.f, 0.95f));
}

float AQTClone::TakeDamage(float Damage, FDamageEvent const& DamageEvent, AController* EventInstigator, AActor* DamageCauser)
{
    if (UQTQuantumComponent* Q = Parent.Get())
    {
        Q->Collapse();
    }
    return Damage;
}

// ---- UQTQuantumComponent ------------------------------------------------------------------------

UQTQuantumComponent::UQTQuantumComponent()
{
    PrimaryComponentTick.bCanEverTick = true;
}

void UQTQuantumComponent::Say(const FString& Text, float Dur) const
{
    if (AQTGameMode* GM = GetWorld() ? GetWorld()->GetAuthGameMode<AQTGameMode>() : nullptr)
    {
        GM->ShowMessage(Text, Dur);
    }
}

bool UQTQuantumComponent::ViewRay(FVector& Eye, FVector& Dir) const
{
    const APawn* Pawn = Cast<APawn>(GetOwner());
    const APlayerController* PC = Pawn ? Cast<APlayerController>(Pawn->GetController()) : nullptr;
    if (!PC)
    {
        return false;
    }
    FRotator Rot;
    PC->GetPlayerViewPoint(Eye, Rot);
    Dir = Rot.Vector();
    return true;
}

void UQTQuantumComponent::TickComponent(float Dt, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction)
{
    Super::TickComponent(Dt, TickType, ThisTickFunction);
    UWorld* World = GetWorld();
    CdBlink = FMath::Max(0.f, CdBlink - Dt);
    CdLink = FMath::Max(0.f, CdLink - Dt);
    CdSuper = FMath::Max(0.f, CdSuper - Dt);
    AddEnergy(8.f * Dt);

    if (bBeacon)
    {
        BeaconT -= Dt;
        DrawDebugCylinder(World, BeaconPos, BeaconPos + FVector(0.f, 0.f, 700.f), 40.f, 12, FColor(120, 250, 255), false, 0.f, 0, 3.f);
        DrawDebugSphere(World, BeaconPos + FVector(0.f, 0.f, 120.f), 45.f, 10, FColor(255, 80, 240), false, 0.f, 0, 3.f);
        if (BeaconT <= 0.f)
        {
            bBeacon = false;
        }
    }

    if (Clone.IsValid())
    {
        CloneT -= Dt;
        if (CloneT <= 0.f)
        {
            Collapse();
        }
    }

    for (int32 i = Links.Num() - 1; i >= 0; --i)
    {
        FQTLink& L = Links[i];
        L.T -= Dt;
        AQTDrone* A = L.A.Get();
        AQTDrone* B = L.B.Get();
        if (L.T <= 0.f || !A || !B || A->IsDead() || B->IsDead())
        {
            if (A) { A->Linked = nullptr; }
            if (B) { B->Linked = nullptr; }
            Links.RemoveAtSwap(i);
            continue;
        }
        DrawDebugLine(World, A->GetActorLocation(), B->GetActorLocation(), FColor(120, 250, 255), false, 0.f, 0, 4.f);
    }
}

void UQTQuantumComponent::Blink()
{
    if (bBeacon)
    {
        Teleport();
        return;
    }
    if (CdBlink > 0.f) { return; }
    if (Energy < 15.f) { Say(TEXT("NOT ENOUGH COHERENCE"), 1.f); return; }

    FVector Eye, Dir;
    if (!ViewRay(Eye, Dir)) { return; }
    FCollisionQueryParams Q(SCENE_QUERY_STAT(QTBlink), false, GetOwner());
    FHitResult Hit;
    FVector P = Eye + Dir * 4800.f;
    if (GetWorld()->LineTraceSingleByChannel(Hit, Eye, P, ECC_Visibility, Q))
    {
        P = Hit.ImpactPoint - Dir * 60.f;
    }
    FHitResult Down;
    if (GetWorld()->LineTraceSingleByChannel(Down, P, P - FVector(0.f, 0.f, 15000.f), ECC_Visibility, Q))
    {
        P = Down.ImpactPoint;
    }
    else
    {
        P.Z = 0.f;
    }
    BeaconPos = P;
    bBeacon = true;
    BeaconT = 8.f;
    Energy -= 15.f;
    CdBlink = 0.3f;
    Say(TEXT("BELL-PAIR BEACON PLACED - BLINK AGAIN TO TELEPORT"), 1.6f);
}

void UQTQuantumComponent::Teleport()
{
    AActor* Owner = GetOwner();
    if (!Owner) { return; }
    float HalfHeight = 90.f;
    if (const ACharacter* C = Cast<ACharacter>(Owner))
    {
        HalfHeight = C->GetCapsuleComponent()->GetScaledCapsuleHalfHeight();
    }
    DrawDebugLine(GetWorld(), Owner->GetActorLocation(), BeaconPos, FColor(120, 250, 255), false, 0.25f, 0, 6.f);
    Owner->TeleportTo(BeaconPos + FVector(0.f, 0.f, HalfHeight + 5.f), Owner->GetActorRotation());
    bBeacon = false;
    CdBlink = 0.4f;

    // The real protocol: Alice's two classical bits tell Bob which corrections to apply (m1 -> X, then m0 -> Z).
    const int32 M0 = FMath::RandBool() ? 1 : 0, M1 = FMath::RandBool() ? 1 : 0;
    FString Fix = TEXT("NOTHING");
    if (M1 && M0) { Fix = TEXT("X THEN Z"); } else if (M1) { Fix = TEXT("X"); } else if (M0) { Fix = TEXT("Z"); }
    Say(FString::Printf(TEXT("TELEPORTED - ALICE BITS %d%d -> BOB APPLIES %s"), M0, M1, *Fix), 2.f);
}

void UQTQuantumComponent::Entangle()
{
    if (CdLink > 0.f) { return; }
    if (Energy < 25.f) { Say(TEXT("NOT ENOUGH COHERENCE"), 1.f); return; }
    FVector Eye, Dir;
    if (!ViewRay(Eye, Dir)) { return; }

    FCollisionQueryParams Q(SCENE_QUERY_STAT(QTEntangle), false, GetOwner());
    FHitResult Hit;
    AQTDrone* A = nullptr;
    if (GetWorld()->SweepSingleByChannel(Hit, Eye, Eye + Dir * 7000.f, FQuat::Identity, ECC_Visibility, FCollisionShape::MakeSphere(150.f), Q))
    {
        A = Cast<AQTDrone>(Hit.GetActor());
    }
    if (!A || A->Linked.IsValid()) { Say(TEXT("NO TARGET IN SIGHT"), 1.f); return; }

    AQTDrone* B = nullptr;
    float Best = 4500.f;
    for (TActorIterator<AQTDrone> It(GetWorld()); It; ++It)
    {
        AQTDrone* D = *It;
        if (D == A || D->IsDead() || D->Linked.IsValid()) { continue; }
        const float Dist = FVector::Dist2D(D->GetActorLocation(), A->GetActorLocation());
        if (Dist < Best) { Best = Dist; B = D; }
    }
    if (!B) { Say(TEXT("NEED A SECOND TARGET WITHIN 45 M"), 1.4f); return; }

    Energy -= 25.f;
    CdLink = 0.8f;
    A->Linked = B;
    B->Linked = A;
    A->Alert();
    B->Alert();
    FQTLink L;
    L.A = A;
    L.B = B;
    Links.Add(L);
    Say(TEXT("ENTANGLED - DAMAGE IS SHARED ACROSS DISTANCE"), 1.8f);
}

void UQTQuantumComponent::Superpose()
{
    if (Clone.IsValid()) { Collapse(); return; }
    if (CdSuper > 0.f) { return; }
    if (Energy < 35.f) { Say(TEXT("NOT ENOUGH COHERENCE"), 1.f); return; }
    AActor* Owner = GetOwner();
    if (!Owner) { return; }

    FActorSpawnParameters Params;
    Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
    AQTClone* C = GetWorld()->SpawnActor<AQTClone>(AQTClone::StaticClass(), Owner->GetActorTransform(), Params);
    if (!C) { return; }
    C->Parent = this;
    Clone = C;
    CloneT = 6.f;
    Energy -= 35.f;
    Say(TEXT("SUPERPOSITION - ENEMIES SEE TWO OF YOU - BE FAST"), 1.8f);
}

void UQTQuantumComponent::Collapse()
{
    AQTClone* C = Clone.Get();
    if (!C) { return; }
    const FVector Loc = C->GetActorLocation();
    AActor* Owner = GetOwner();
    const APawn* Pawn = Cast<APawn>(Owner);
    UGameplayStatics::ApplyRadialDamage(GetWorld(), 70.f, Loc, 900.f, UDamageType::StaticClass(), TArray<AActor*>(), Owner, Pawn ? Pawn->GetController() : nullptr, true);
    DrawDebugSphere(GetWorld(), Loc, 900.f, 24, FColor(100, 255, 238), false, 0.4f, 0, 6.f);
    Clone = nullptr;
    C->Destroy();
    CdSuper = 1.5f;
    Say(TEXT("WAVEFUNCTION COLLAPSE"), 1.4f);
}
