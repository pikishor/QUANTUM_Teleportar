#pragma once

#include "CoreMinimal.h"
#include "GameFramework/PlayerController.h"
#include "QTPlayerController.generated.h"

struct FQTTouchButton
{
    FName Id;
    FString Label;
    FVector2D Center = FVector2D::ZeroVector;
    float Radius = 40.f;
    int32 Finger = -1;   // finger currently holding the button, -1 when idle
};

// Polls keyboard/mouse every frame and runs a code-drawn touch overlay on phones, so no input assets are needed.
// Left half of the screen = move stick, right half = look, round buttons = actions (drawn by AQTHUD).
UCLASS()
class QUANTUMTELEPORTAR_API AQTPlayerController : public APlayerController
{
    GENERATED_BODY()

public:
    virtual void BeginPlay() override;
    virtual void SetupInputComponent() override;
    virtual void PlayerTick(float Dt) override;

    /** Console: "QTTouchUI 1" previews the mobile overlay in the editor. */
    UFUNCTION(Exec)
    void QTTouchUI(bool bOn);

    void LayoutButtons();

    bool bTouchUI = false;
    TArray<FQTTouchButton> Buttons;
    FVector2D StickOrigin = FVector2D::ZeroVector;
    FVector2D StickVec = FVector2D::ZeroVector;
    float UIScale = 1.f;

private:
    void TouchDown(ETouchIndex::Type Finger, FVector Location);
    void TouchUp(ETouchIndex::Type Finger, FVector Location);
    void TouchMove(ETouchIndex::Type Finger, FVector Location);
    bool IsHeld(FName Id) const;

    TArray<FName> Pending;
    int32 StickFinger = -1;
    int32 LookFinger = -1;
    FVector2D LastLook = FVector2D::ZeroVector;
};
