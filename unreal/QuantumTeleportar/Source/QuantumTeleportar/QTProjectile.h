#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "QTProjectile.generated.h"

class USphereComponent;
class UProjectileMovementComponent;
class UStaticMeshComponent;

// Energy bolt fired by Observer drones.
UCLASS()
class QUANTUMTELEPORTAR_API AQTProjectile : public AActor
{
    GENERATED_BODY()

public:
    AQTProjectile();
    void Launch(const FVector& Dir, float Speed, float InDamage, const FLinearColor& Color);

protected:
    UFUNCTION()
    void OnHit(UPrimitiveComponent* HitComp, AActor* Other, UPrimitiveComponent* OtherComp, FVector NormalImpulse, const FHitResult& Hit);

    UPROPERTY() USphereComponent* Sphere;
    UPROPERTY() UProjectileMovementComponent* Movement;
    UPROPERTY() UStaticMeshComponent* Mesh;
    float Damage = 8.f;
};
