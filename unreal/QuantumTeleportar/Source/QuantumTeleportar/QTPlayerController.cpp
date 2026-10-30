#include "QTPlayerController.h"
#include "QTCharacter.h"
#include "QTQuantumComponent.h"
#include "Camera/PlayerCameraManager.h"
#include "Components/InputComponent.h"
#include "GameFramework/PlayerInput.h"

void AQTPlayerController::BeginPlay()
{
    Super::BeginPlay();
    SetInputMode(FInputModeGameOnly());
    bShowMouseCursor = false;
    if (PlayerCameraManager)
    {
        PlayerCameraManager->ViewPitchMin = -60.f;
        PlayerCameraManager->ViewPitchMax = 60.f;
    }
#if PLATFORM_ANDROID || PLATFORM_IOS
    bTouchUI = true;
#endif
}

void AQTPlayerController::SetupInputComponent()
{
    Super::SetupInputComponent();
    InputComponent->BindTouch(IE_Pressed, this, &AQTPlayerController::TouchDown);
    InputComponent->BindTouch(IE_Released, this, &AQTPlayerController::TouchUp);
    InputComponent->BindTouch(IE_Repeat, this, &AQTPlayerController::TouchMove);
}

void AQTPlayerController::QTTouchUI(bool bOn)
{
    bTouchUI = bOn;
}

void AQTPlayerController::LayoutButtons()
{
    int32 W = 0, H = 0;
    GetViewportSize(W, H);
    UIScale = FMath::Max(0.5f, H / 720.f);
    const float S = UIScale;
    auto Put = [&](const TCHAR* Id, const TCHAR* Label, float FromRight, float FromBottom, float Radius)
    {
        FQTTouchButton* B = Buttons.FindByPredicate([&](const FQTTouchButton& X) { return X.Id == FName(Id); });
        if (!B) { B = &Buttons.AddDefaulted_GetRef(); B->Id = FName(Id); }
        B->Label = Label;
        B->Center = FVector2D(W - FromRight * S, H - FromBottom * S);
        B->Radius = Radius * S;
    };
    Put(TEXT("fire"), TEXT("FIRE"), 90.f, 90.f, 52.f);
    Put(TEXT("jump"), TEXT("JUMP"), 200.f, 62.f, 34.f);
    Put(TEXT("reload"), TEXT("R"), 56.f, 190.f, 28.f);
    Put(TEXT("aim"), TEXT("AIM"), 140.f, 170.f, 28.f);
    Put(TEXT("blink"), TEXT("BLINK"), 56.f, 262.f, 32.f);
    Put(TEXT("link"), TEXT("LINK"), 142.f, 250.f, 32.f);
    Put(TEXT("super"), TEXT("SUPER"), 226.f, 170.f, 32.f);
}

bool AQTPlayerController::IsHeld(FName Id) const
{
    for (const FQTTouchButton& B : Buttons)
    {
        if (B.Id == Id && B.Finger >= 0) { return true; }
    }
    return false;
}

void AQTPlayerController::TouchDown(ETouchIndex::Type Finger, FVector Location)
{
    if (!bTouchUI) { return; }
    LayoutButtons();
    int32 W = 0, H = 0;
    GetViewportSize(W, H);
    const FVector2D P(Location.X, Location.Y);
    for (FQTTouchButton& B : Buttons)
    {
        if (FVector2D::Distance(P, B.Center) <= B.Radius * 1.25f)
        {
            B.Finger = static_cast<int32>(Finger);
            Pending.Add(B.Id);
            return;
        }
    }
    if (P.X < W * 0.45f)
    {
        if (StickFinger < 0) { StickFinger = static_cast<int32>(Finger); StickOrigin = P; StickVec = FVector2D::ZeroVector; }
    }
    else if (LookFinger < 0)
    {
        LookFinger = static_cast<int32>(Finger);
        LastLook = P;
    }
}

void AQTPlayerController::TouchUp(ETouchIndex::Type Finger, FVector Location)
{
    const int32 F = static_cast<int32>(Finger);
    for (FQTTouchButton& B : Buttons)
    {
        if (B.Finger == F) { B.Finger = -1; }
    }
    if (F == StickFinger) { StickFinger = -1; StickVec = FVector2D::ZeroVector; }
    if (F == LookFinger) { LookFinger = -1; }
}

void AQTPlayerController::TouchMove(ETouchIndex::Type Finger, FVector Location)
{
    const int32 F = static_cast<int32>(Finger);
    const FVector2D P(Location.X, Location.Y);
    if (F == StickFinger)
    {
        FVector2D D = (P - StickOrigin) / (60.f * UIScale);
        if (D.Size() > 1.0) { D = D.GetSafeNormal(); }
        StickVec = FVector2D(D.X, -D.Y);   // screen up = forward
    }
    else if (F == LookFinger)
    {
        const FVector2D Delta = P - LastLook;
        LastLook = P;
        AddYawInput(static_cast<float>(Delta.X) * 0.12f);
        AddPitchInput(static_cast<float>(Delta.Y) * 0.12f);
    }
}

void AQTPlayerController::PlayerTick(float Dt)
{
    Super::PlayerTick(Dt);
    AQTCharacter* C = Cast<AQTCharacter>(GetPawn());
    if (!C) { return; }

    FVector2D Move = FVector2D::ZeroVector;
    if (IsInputKeyDown(EKeys::W) || IsInputKeyDown(EKeys::Up)) { Move.Y += 1.0; }
    if (IsInputKeyDown(EKeys::S) || IsInputKeyDown(EKeys::Down)) { Move.Y -= 1.0; }
    if (IsInputKeyDown(EKeys::D) || IsInputKeyDown(EKeys::Right)) { Move.X += 1.0; }
    if (IsInputKeyDown(EKeys::A) || IsInputKeyDown(EKeys::Left)) { Move.X -= 1.0; }
    bool bFire = IsInputKeyDown(EKeys::LeftMouseButton);
    bool bAim = IsInputKeyDown(EKeys::RightMouseButton);
    bool bSprint = IsInputKeyDown(EKeys::LeftShift);

    float Dx = 0.f, Dy = 0.f;
    GetInputMouseDelta(Dx, Dy);
    if (Dx != 0.f || Dy != 0.f)
    {
        AddYawInput(Dx);
        AddPitchInput(-Dy);   // mouse up = look up
    }

    if (WasInputKeyJustPressed(EKeys::SpaceBar)) { C->Jump(); }
    if (WasInputKeyJustPressed(EKeys::Q)) { C->Quantum->Blink(); }
    if (WasInputKeyJustPressed(EKeys::E)) { C->Quantum->Entangle(); }
    if (WasInputKeyJustPressed(EKeys::G)) { C->Quantum->Superpose(); }
    if (WasInputKeyJustPressed(EKeys::R)) { C->StartReload(); }

    if (bTouchUI)
    {
        LayoutButtons();
        Move += StickVec;
        bSprint = bSprint || StickVec.Size() > 0.92;
        bFire = bFire || IsHeld(TEXT("fire"));
        bAim = bAim || IsHeld(TEXT("aim"));
        for (const FName& Action : Pending)
        {
            if (Action == TEXT("jump")) { C->Jump(); }
            else if (Action == TEXT("blink")) { C->Quantum->Blink(); }
            else if (Action == TEXT("link")) { C->Quantum->Entangle(); }
            else if (Action == TEXT("super")) { C->Quantum->Superpose(); }
            else if (Action == TEXT("reload")) { C->StartReload(); }
        }
    }
    Pending.Reset();

    if (Move.Size() > 1.0) { Move = Move.GetSafeNormal(); }
    C->SetMoveInput(Move);
    C->SetFire(bFire);
    C->SetAim(bAim);
    C->SetSprint(bSprint);
}
