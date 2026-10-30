#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "QTCore.generated.h"

class USphereComponent;
class UStaticMeshComponent;

// Quantum core: the sector objective. A tall beam marks it from across the city.
UCLASS()
class QUANTUMTELEPORTAR_API AQTCore : public AActor
{
    GENERATED_BODY()

public:
    AQTCore();
    virtual void Tick(float Dt) override;

protected:
    virtual void BeginPlay() override;

    UFUNCTION()
    void OnOverlap(UPrimitiveComponent* OverlappedComp, AActor* Other, UPrimitiveComponent* OtherComp, int32 BodyIndex, bool bFromSweep, const FHitResult& Sweep);

    UPROPERTY() USphereComponent* Trigger;
    UPROPERTY() UStaticMeshComponent* Gem;
    UPROPERTY() UStaticMeshComponent* Beam;
};
