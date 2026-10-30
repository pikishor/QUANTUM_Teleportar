#pragma once

#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "GameFramework/Actor.h"
#include "QTQuantumComponent.generated.h"

class AQTDrone;
class UQTQuantumComponent;
class UStaticMeshComponent;
class USphereComponent;

// Holographic decoy left behind by Superposition. Drones may target it; shooting it collapses it early.
UCLASS()
class QUANTUMTELEPORTAR_API AQTClone : public AActor
{
    GENERATED_BODY()

public:
    AQTClone();
    TWeakObjectPtr<UQTQuantumComponent> Parent;
    virtual float TakeDamage(float Damage, struct FDamageEvent const& DamageEvent, AController* EventInstigator, AActor* DamageCauser) override;

protected:
    virtual void BeginPlay() override;

    UPROPERTY() USphereComponent* Sphere;
    UPROPERTY() UStaticMeshComponent* Body;
};

struct FQTLink
{
    TWeakObjectPtr<AQTDrone> A;
    TWeakObjectPtr<AQTDrone> B;
    float T = 9.f;
};

// Blink (teleport to a thrown Bell-pair beacon), Entangle (shared damage), Superposition (decoy -> collapse blast).
UCLASS(ClassGroup = (Custom), meta = (BlueprintSpawnableComponent))
class QUANTUMTELEPORTAR_API UQTQuantumComponent : public UActorComponent
{
    GENERATED_BODY()

public:
    UQTQuantumComponent();
    virtual void TickComponent(float Dt, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction) override;

    void Blink();
    void Entangle();
    void Superpose();
    void Collapse();

    void AddEnergy(float V) { Energy = FMath::Min(MaxEnergy, Energy + V); }
    AQTClone* GetClone() const { return Clone.Get(); }
    bool HasClone() const { return Clone.IsValid(); }
    bool HasBeacon() const { return bBeacon; }
    FVector GetBeaconPos() const { return BeaconPos; }

    float Energy = 100.f;
    float MaxEnergy = 100.f;
    float CdBlink = 0.f, CdLink = 0.f, CdSuper = 0.f;

private:
    void Teleport();
    void Say(const FString& Text, float Dur = 2.f) const;
    bool ViewRay(FVector& Eye, FVector& Dir) const;

    bool bBeacon = false;
    FVector BeaconPos = FVector::ZeroVector;
    float BeaconT = 0.f;
    TWeakObjectPtr<AQTClone> Clone;
    float CloneT = 0.f;
    TArray<FQTLink> Links;
};
