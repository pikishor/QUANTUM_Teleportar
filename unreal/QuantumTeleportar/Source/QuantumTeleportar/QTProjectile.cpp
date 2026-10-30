#include "QTProjectile.h"
#include "QTCommon.h"
#include "QTDrone.h"
#include "Components/SphereComponent.h"
#include "Components/StaticMeshComponent.h"
#include "GameFramework/DamageType.h"
#include "GameFramework/ProjectileMovementComponent.h"
#include "Kismet/GameplayStatics.h"

AQTProjectile::AQTProjectile()
{
    PrimaryActorTick.bCanEverTick = false;
    InitialLifeSpan = 3.f;

    Sphere = CreateDefaultSubobject<USphereComponent>(TEXT("Sphere"));
    Sphere->InitSphereRadius(18.f);
    Sphere->SetCollisionProfileName(TEXT("BlockAllDynamic"));
    Sphere->OnComponentHit.AddDynamic(this, &AQTProjectile::OnHit);
    SetRootComponent(Sphere);

    Mesh = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("Mesh"));
    Mesh->SetupAttachment(Sphere);
    Mesh->SetCollisionEnabled(ECollisionEnabled::NoCollision);
    if (UStaticMesh* Shape = QT::LoadShape(TEXT("/Engine/BasicShapes/Sphere.Sphere")))
    {
        Mesh->SetStaticMesh(Shape);
    }
    Mesh->SetRelativeScale3D(FVector(0.36f));

    Movement = CreateDefaultSubobject<UProjectileMovementComponent>(TEXT("Movement"));
    Movement->ProjectileGravityScale = 0.f;
    Movement->InitialSpeed = 3000.f;
    Movement->MaxSpeed = 3000.f;
}

void AQTProjectile::Launch(const FVector& Dir, float Speed, float InDamage, const FLinearColor& Color)
{
    Damage = InDamage;
    Movement->MaxSpeed = Speed;
    Movement->Velocity = Dir * Speed;
    if (AActor* Shooter = GetOwner())
    {
        Sphere->IgnoreActorWhenMoving(Shooter, true);
    }
    QT::Tint(Mesh, Color);
}

void AQTProjectile::OnHit(UPrimitiveComponent* HitComp, AActor* Other, UPrimitiveComponent* OtherComp, FVector NormalImpulse, const FHitResult& Hit)
{
    // drones do not damage each other
    if (Other && Other != GetOwner() && !Other->IsA<AQTDrone>())
    {
        UGameplayStatics::ApplyDamage(Other, Damage, nullptr, this, UDamageType::StaticClass());
    }
    Destroy();
}
