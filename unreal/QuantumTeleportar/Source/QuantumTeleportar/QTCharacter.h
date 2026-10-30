#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Character.h"
#include "QTCharacter.generated.h"

class USpringArmComponent;
class UCameraComponent;
class UStaticMeshComponent;
class UQTQuantumComponent;

// Third-person shooter pawn: strafe-style movement, hitscan rifle, quantum powers.
// Input is polled by AQTPlayerController (keyboard/mouse and the touch overlay) and pushed in through this API.
UCLASS()
class QUANTUMTELEPORTAR_API AQTCharacter : public ACharacter
{
    GENERATED_BODY()

public:
    AQTCharacter();

    virtual void BeginPlay() override;
    virtual void Tick(float Dt) override;
    virtual float TakeDamage(float Damage, struct FDamageEvent const& DamageEvent, AController* EventInstigator, AActor* DamageCauser) override;

    void SetMoveInput(const FVector2D& In) { MoveIn = In; }
    void SetFire(bool bOn) { bFire = bOn; }
    void SetAim(bool bOn) { bAim = bOn; }
    void SetSprint(bool bOn) { bSprint = bOn; }
    void StartReload();

    bool IsReloading() const { return ReloadT > 0.f; }
    bool IsAiming() const { return bAim; }

    UPROPERTY(VisibleAnywhere) UQTQuantumComponent* Quantum;

    float Health = 100.f;
    float MaxHealth = 100.f;
    int32 Ammo = 30;
    int32 Mag = 30;
    float Spread = 0.f;

private:
    void Fire();

    UPROPERTY(VisibleAnywhere) USpringArmComponent* SpringArm;
    UPROPERTY(VisibleAnywhere) UCameraComponent* Camera;
    UPROPERTY(VisibleAnywhere) UStaticMeshComponent* Body;
    UPROPERTY(VisibleAnywhere) UStaticMeshComponent* Visor;

    FVector2D MoveIn = FVector2D::ZeroVector;
    bool bFire = false, bAim = false, bSprint = false, bDead = false;
    float FireT = 0.f, ReloadT = 0.f, LastHurt = -99.f;
};
