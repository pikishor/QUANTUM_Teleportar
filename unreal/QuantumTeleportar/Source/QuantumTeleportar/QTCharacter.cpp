#include "QTCharacter.h"
#include "QTCommon.h"
#include "QTDrone.h"
#include "QTGameMode.h"
#include "QTQuantumComponent.h"
#include "Camera/CameraComponent.h"
#include "Components/CapsuleComponent.h"
#include "Components/StaticMeshComponent.h"
#include "DrawDebugHelpers.h"
#include "Engine/World.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "GameFramework/DamageType.h"
#include "GameFramework/PlayerController.h"
#include "GameFramework/SpringArmComponent.h"
#include "Kismet/GameplayStatics.h"

AQTCharacter::AQTCharacter()
{
    PrimaryActorTick.bCanEverTick = true;

    bUseControllerRotationYaw = true;   // strafe-style third person: the body always faces the aim direction
    UCharacterMovementComponent* Move = GetCharacterMovement();
    Move->bOrientRotationToMovement = false;
    Move->MaxWalkSpeed = 620.f;
    Move->JumpZVelocity = 760.f;
    Move->AirControl = 0.35f;

    SpringArm = CreateDefaultSubobject<USpringArmComponent>(TEXT("SpringArm"));
    SpringArm->SetupAttachment(RootComponent);
    SpringArm->TargetArmLength = 360.f;
    SpringArm->SocketOffset = FVector(0.f, 80.f, 45.f);   // over-the-shoulder
    SpringArm->bUsePawnControlRotation = true;

    Camera = CreateDefaultSubobject<UCameraComponent>(TEXT("Camera"));
    Camera->SetupAttachment(SpringArm, USpringArmComponent::SocketName);
    Camera->FieldOfView = 90.f;

    // Graybox body; swap for a skeletal mesh + animation blueprint when art exists.
    UStaticMesh* CylinderShape = QT::LoadShape(TEXT("/Engine/BasicShapes/Cylinder.Cylinder"));
    UStaticMesh* CubeShape = QT::LoadShape(TEXT("/Engine/BasicShapes/Cube.Cube"));
    Body = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("Body"));
    Body->SetupAttachment(RootComponent);
    Body->SetCollisionEnabled(ECollisionEnabled::NoCollision);
    if (CylinderShape) { Body->SetStaticMesh(CylinderShape); }
    Body->SetRelativeScale3D(FVector(0.55f, 0.55f, 1.7f));
    Visor = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("Visor"));
    Visor->SetupAttachment(RootComponent);
    Visor->SetCollisionEnabled(ECollisionEnabled::NoCollision);
    if (CubeShape) { Visor->SetStaticMesh(CubeShape); }
    Visor->SetRelativeLocation(FVector(26.f, 0.f, 60.f));
    Visor->SetRelativeScale3D(FVector(0.12f, 0.4f, 0.1f));

    Quantum = CreateDefaultSubobject<UQTQuantumComponent>(TEXT("Quantum"));
}

void AQTCharacter::BeginPlay()
{
    Super::BeginPlay();
    QT::Tint(Body, FLinearColor(0.08f, 0.12f, 0.35f));
    QT::Tint(Visor, FLinearColor(0.3f, 0.95f, 1.f));
}

void AQTCharacter::StartReload()
{
    if (ReloadT <= 0.f && Ammo < Mag)
    {
        ReloadT = 1.3f;
    }
}

float AQTCharacter::TakeDamage(float Damage, FDamageEvent const& DamageEvent, AController* EventInstigator, AActor* DamageCauser)
{
    const float Applied = Super::TakeDamage(Damage, DamageEvent, EventInstigator, DamageCauser);
    if (bDead) { return 0.f; }
    Health -= Damage;
    LastHurt = GetWorld()->GetTimeSeconds();
    if (Health <= 0.f)
    {
        bDead = true;
        if (AQTGameMode* GM = GetWorld()->GetAuthGameMode<AQTGameMode>())
        {
            GM->OnPlayerDied();
        }
    }
    return Applied;
}

void AQTCharacter::Tick(float Dt)
{
    Super::Tick(Dt);
    if (bDead) { return; }

    const bool bCloned = Quantum && Quantum->HasClone();
    const float Base = bAim ? 340.f : (bSprint && MoveIn.Y > 0.3f ? 1000.f : 620.f);
    GetCharacterMovement()->MaxWalkSpeed = Base * (bCloned ? 1.3f : 1.f);
    AddMovementInput(GetActorForwardVector(), static_cast<float>(MoveIn.Y));
    AddMovementInput(GetActorRightVector(), static_cast<float>(MoveIn.X));

    Camera->SetFieldOfView(FMath::FInterpTo(Camera->FieldOfView, bAim ? 55.f : 90.f, Dt, 10.f));
    SpringArm->TargetArmLength = FMath::FInterpTo(SpringArm->TargetArmLength, bAim ? 220.f : 360.f, Dt, 10.f);

    FireT -= Dt;
    Spread = FMath::Max(0.f, Spread - 0.08f * Dt);
    if (ReloadT > 0.f)
    {
        ReloadT -= Dt;
        if (ReloadT <= 0.f) { Ammo = Mag; }
    }
    if (bFire && ReloadT <= 0.f)
    {
        if (Ammo <= 0) { StartReload(); }
        else if (FireT <= 0.f) { Fire(); }
    }

    if (GetWorld()->GetTimeSeconds() - LastHurt > 5.f)
    {
        Health = FMath::Min(MaxHealth, Health + 14.f * Dt);
    }
}

void AQTCharacter::Fire()
{
    FireT = 0.11f;
    --Ammo;
    Spread = FMath::Min(0.03f, Spread + 0.003f);

    APlayerController* PC = Cast<APlayerController>(GetController());
    if (!PC) { return; }
    FVector Eye;
    FRotator Rot;
    PC->GetPlayerViewPoint(Eye, Rot);

    const bool bMoving = GetVelocity().SizeSquared2D() > 10000.f;
    const float Cone = (bAim ? 0.004f : 0.014f) + Spread + (bMoving ? 0.01f : 0.f);
    const FVector Dir = FMath::VRandCone(Rot.Vector(), Cone);
    const FVector End = Eye + Dir * 25000.f;

    FCollisionQueryParams Q(SCENE_QUERY_STAT(QTFire), false, this);
    FHitResult Hit;
    const bool bHit = GetWorld()->LineTraceSingleByChannel(Hit, Eye, End, ECC_Visibility, Q);
    const FVector Impact = bHit ? FVector(Hit.ImpactPoint) : End;
    const FVector Muzzle = GetActorLocation() + GetActorForwardVector() * 70.f + GetActorRightVector() * 30.f + FVector(0.f, 0.f, 45.f);
    DrawDebugLine(GetWorld(), Muzzle, Impact, FColor(255, 235, 140), false, 0.06f, 0, 2.f);   // tracer placeholder

    if (bHit && Hit.GetActor())
    {
        float Dmg = 14.f;
        if (const AQTDrone* Drone = Cast<AQTDrone>(Hit.GetActor()))
        {
            if (Impact.Z > Drone->GetActorLocation().Z + 40.f * Drone->Scale()) { Dmg = 30.f; }   // headshot
        }
        UGameplayStatics::ApplyPointDamage(Hit.GetActor(), Dmg, Dir, Hit, GetController(), this, UDamageType::StaticClass());
    }

    AddControllerPitchInput(-0.12f * FMath::FRandRange(0.5f, 1.f));   // recoil
    AddControllerYawInput(FMath::FRandRange(-0.08f, 0.08f));
}
