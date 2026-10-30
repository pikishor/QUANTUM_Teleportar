#include "QTCore.h"
#include "QTCharacter.h"
#include "QTCommon.h"
#include "QTGameMode.h"
#include "Components/SphereComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Engine/World.h"

AQTCore::AQTCore()
{
    PrimaryActorTick.bCanEverTick = true;

    Trigger = CreateDefaultSubobject<USphereComponent>(TEXT("Trigger"));
    Trigger->InitSphereRadius(380.f);
    Trigger->SetCollisionProfileName(TEXT("OverlapAllDynamic"));
    Trigger->SetGenerateOverlapEvents(true);
    Trigger->OnComponentBeginOverlap.AddDynamic(this, &AQTCore::OnOverlap);
    SetRootComponent(Trigger);

    UStaticMesh* SphereShape = QT::LoadShape(TEXT("/Engine/BasicShapes/Sphere.Sphere"));
    UStaticMesh* CubeShape = QT::LoadShape(TEXT("/Engine/BasicShapes/Cube.Cube"));

    Gem = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("Gem"));
    Gem->SetupAttachment(Trigger);
    Gem->SetCollisionEnabled(ECollisionEnabled::NoCollision);
    if (SphereShape) { Gem->SetStaticMesh(SphereShape); }
    Gem->SetRelativeLocation(FVector(0.f, 0.f, 220.f));
    Gem->SetRelativeScale3D(FVector(1.6f));

    Beam = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("Beam"));
    Beam->SetupAttachment(Trigger);
    Beam->SetCollisionEnabled(ECollisionEnabled::NoCollision);
    if (CubeShape) { Beam->SetStaticMesh(CubeShape); }
    Beam->SetRelativeLocation(FVector(0.f, 0.f, 8000.f));
    Beam->SetRelativeScale3D(FVector(0.8f, 0.8f, 160.f));
}

void AQTCore::BeginPlay()
{
    Super::BeginPlay();
    QT::Tint(Gem, FLinearColor(1.f, 0.2f, 0.9f));
    QT::Tint(Beam, FLinearColor(1.f, 0.35f, 0.95f));
}

void AQTCore::Tick(float Dt)
{
    Super::Tick(Dt);
    Gem->AddLocalRotation(FRotator(0.f, 90.f * Dt, 0.f));
}

void AQTCore::OnOverlap(UPrimitiveComponent* OverlappedComp, AActor* Other, UPrimitiveComponent* OtherComp, int32 BodyIndex, bool bFromSweep, const FHitResult& Sweep)
{
    if (!Cast<AQTCharacter>(Other)) { return; }
    if (AQTGameMode* GM = GetWorld()->GetAuthGameMode<AQTGameMode>())
    {
        GM->OnCoreCollected();
    }
    Destroy();
}
