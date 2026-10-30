#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "QTDrone.generated.h"

class USphereComponent;
class UStaticMeshComponent;

UENUM()
enum class EQTDroneType : uint8
{
    Sentinel,
    Striker,
    Heavy
};

// Tuning values, ported 1:1 from the web prototype (metres -> centimetres).
struct FQTDroneSpec
{
    float Hp = 60.f;
    float Speed = 460.f;
    float Range = 2200.f;
    float FireMin = 1.f;
    float FireMax = 1.7f;
    float Damage = 7.f;
    float BoltSpeed = 3000.f;
    float Scale = 1.f;
    float Score = 50.f;
    float Heat = 0.22f;
    int32 Burst = 1;
    bool bKamikaze = false;
    FLinearColor Color = FLinearColor(1.f, 0.24f, 0.37f);

    static FQTDroneSpec For(EQTDroneType Type);
};

// Observer drone: hovers, patrols, chases and shoots (Sentinel / Heavy) or rams (Striker).
UCLASS()
class QUANTUMTELEPORTAR_API AQTDrone : public AActor
{
    GENERATED_BODY()

public:
    AQTDrone();

    /** Call between SpawnActorDeferred and FinishSpawning. */
    void InitType(EQTDroneType InType, bool bStartAware);

    virtual void Tick(float Dt) override;
    virtual float TakeDamage(float Damage, struct FDamageEvent const& DamageEvent, AController* EventInstigator, AActor* DamageCauser) override;

    void ApplyHit(float Damage, bool bMirrored);
    void Alert() { bAware = true; }
    bool IsDead() const { return bDead; }
    bool IsAware() const { return bAware; }
    float Scale() const { return Spec.Scale; }

    /** Entanglement partner: damage to one is mirrored to the other. */
    TWeakObjectPtr<AQTDrone> Linked;
    bool bReinforcement = false;

protected:
    virtual void BeginPlay() override;

private:
    void Die();
    void Fire(const FVector& Target);

    UPROPERTY() USphereComponent* Sphere;
    UPROPERTY() UStaticMeshComponent* Hull;
    UPROPERTY() UStaticMeshComponent* Eye;
    UPROPERTY() UStaticMeshComponent* Ring;

    FQTDroneSpec Spec;
    EQTDroneType Type = EQTDroneType::Sentinel;
    float Hp = 60.f, MaxHp = 60.f;
    float T = 0.f, FireT = 1.f, RetargetT = 0.f, LosT = 0.f, StrafeT = 1.f, WanderT = 0.f, BarT = 0.f, BurstT = 0.f;
    float Strafe = 1.f, WanderYaw = 0.f;
    int32 BurstLeft = 0;
    bool bAware = false, bDead = false, bLos = false, bTargetClone = false;
    FVector Home = FVector::ZeroVector;
};
