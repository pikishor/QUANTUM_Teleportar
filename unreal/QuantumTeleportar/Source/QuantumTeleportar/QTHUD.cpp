#include "QTHUD.h"
#include "QTCharacter.h"
#include "QTCore.h"
#include "QTDrone.h"
#include "QTGameMode.h"
#include "QTPlayerController.h"
#include "QTQuantumComponent.h"
#include "Engine/Canvas.h"
#include "Engine/World.h"
#include "EngineUtils.h"

void AQTHUD::DrawHUD()
{
    Super::DrawHUD();
    const AQTCharacter* C = Cast<AQTCharacter>(GetOwningPawn());
    AQTPlayerController* PC = Cast<AQTPlayerController>(GetOwningPlayerController());
    AQTGameMode* GM = GetWorld() ? GetWorld()->GetAuthGameMode<AQTGameMode>() : nullptr;
    if (!C || !PC || !GM || !Canvas)
    {
        return;
    }

    const float W = Canvas->ClipX, H = Canvas->ClipY;
    const float S = FMath::Clamp(H / 720.f, 0.6f, 2.5f);
    const FLinearColor White(1.f, 1.f, 1.f, 0.85f), Cyan(0.3f, 0.95f, 1.f, 1.f), Red(1.f, 0.27f, 0.4f, 1.f), Dim(0.02f, 0.01f, 0.08f, 0.7f);

    // crosshair
    const float Cx = W * 0.5f, Cy = H * 0.5f, Gap = (C->IsAiming() ? 5.f : 9.f + C->Spread * 300.f) * S;
    DrawLine(Cx - Gap - 8.f * S, Cy, Cx - Gap, Cy, White, 2.f);
    DrawLine(Cx + Gap, Cy, Cx + Gap + 8.f * S, Cy, White, 2.f);
    DrawLine(Cx, Cy - Gap - 8.f * S, Cx, Cy - Gap, White, 2.f);
    DrawLine(Cx, Cy + Gap, Cx, Cy + Gap + 8.f * S, White, 2.f);

    // bars (top right)
    const float Bw = 220.f * S, Bh = 14.f * S, Bx = W - Bw - 16.f * S;
    DrawRect(Dim, Bx, 14.f * S, Bw, Bh);
    DrawRect(Red, Bx, 14.f * S, Bw * FMath::Clamp(C->Health / C->MaxHealth, 0.f, 1.f), Bh);
    DrawText(TEXT("INTEGRITY"), White, Bx + 4.f * S, 12.f * S, nullptr, 0.7f * S, false);
    DrawRect(Dim, Bx, 36.f * S, Bw, Bh);
    DrawRect(Cyan, Bx, 36.f * S, Bw * FMath::Clamp(C->Quantum->Energy / C->Quantum->MaxEnergy, 0.f, 1.f), Bh);
    DrawText(TEXT("COHERENCE"), FLinearColor(0.f, 0.05f, 0.1f, 1.f), Bx + 4.f * S, 34.f * S, nullptr, 0.7f * S, false);
    const FString Ammo = C->IsReloading() ? FString(TEXT("RELOADING")) : FString::Printf(TEXT("%d / INF"), C->Ammo);
    DrawText(Ammo, White, Bx, 58.f * S, nullptr, 1.4f * S, false);

    // observation level + score (top centre)
    const int32 Stars = FMath::CeilToInt(GM->Heat - 0.001f);
    FString Heat = TEXT("OBSERVATION ");
    for (int32 i = 0; i < 5; ++i) { Heat += i < Stars ? TEXT("* ") : TEXT("- "); }
    DrawText(Heat, Stars > 0 ? Red : White, W * 0.5f - 110.f * S, 12.f * S, nullptr, 1.1f * S, false);
    DrawText(FString::Printf(TEXT("CREDITS %d"), FMath::FloorToInt(GM->Score)), Cyan, W * 0.5f - 50.f * S, 34.f * S, nullptr, 0.9f * S, false);
    DrawText(FString::Printf(TEXT("CORES %d/%d"), GM->CoresGot, GM->CoresTotal), FLinearColor(1.f, 0.5f, 0.95f), W * 0.5f - 40.f * S, 54.f * S, nullptr, 0.9f * S, false);

    // power status (bottom left)
    const UQTQuantumComponent* Q = C->Quantum;
    const float Py = H - 30.f * S;
    DrawText(Q->HasBeacon() ? TEXT("[Q] TELEPORT") : TEXT("[Q] BLINK"), Q->HasBeacon() ? Cyan : White, 16.f * S, Py, nullptr, 0.8f * S, false);
    DrawText(TEXT("[E] ENTANGLE"), Q->Energy >= 25.f ? White : FLinearColor(0.5f, 0.5f, 0.5f), 130.f * S, Py, nullptr, 0.8f * S, false);
    DrawText(Q->HasClone() ? TEXT("[G] COLLAPSE") : TEXT("[G] SUPERPOSE"), Q->HasClone() ? Cyan : White, 270.f * S, Py, nullptr, 0.8f * S, false);

    // message
    if (GM->MessageT > 0.f)
    {
        DrawText(GM->Message, FLinearColor(1.f, 0.92f, 1.f, FMath::Clamp(GM->MessageT, 0.f, 1.f)), W * 0.5f - GM->Message.Len() * 5.5f * S, H * 0.28f, nullptr, 1.1f * S, false);
    }

    // radar (top left): forward is up
    const float Rr = 70.f * S, Rx = 20.f * S + Rr, Ry = 20.f * S + Rr, Scale = Rr / 7000.f;
    DrawRect(Dim, Rx - Rr, Ry - Rr, Rr * 2.f, Rr * 2.f);
    const FVector Pl = C->GetActorLocation();
    const float Yaw = FMath::DegreesToRadians(PC->GetControlRotation().Yaw);
    auto Plot = [&](const FVector& Where, const FLinearColor& Col, float Size)
    {
        const float Dx = static_cast<float>(Where.X - Pl.X), Dy = static_cast<float>(Where.Y - Pl.Y);
        float Sx = (-Dx * FMath::Sin(Yaw) + Dy * FMath::Cos(Yaw)) * Scale;
        float Sy = -(Dx * FMath::Cos(Yaw) + Dy * FMath::Sin(Yaw)) * Scale;
        const float Len = FMath::Sqrt(Sx * Sx + Sy * Sy), Lim = Rr - 5.f * S;
        if (Len > Lim) { Sx *= Lim / Len; Sy *= Lim / Len; }
        DrawRect(Col, Rx + Sx - Size * 0.5f, Ry + Sy - Size * 0.5f, Size, Size);
    };
    for (TActorIterator<AQTDrone> It(GetWorld()); It; ++It)
    {
        if (!It->IsDead()) { Plot(It->GetActorLocation(), It->IsAware() ? Red : FLinearColor(0.6f, 0.25f, 0.35f), 5.f * S); }
    }
    for (const TWeakObjectPtr<AQTCore>& Core : GM->Cores)
    {
        if (const AQTCore* K = Core.Get()) { Plot(K->GetActorLocation(), FLinearColor(1.f, 0.35f, 0.95f), 8.f * S); }
    }
    if (Q->HasBeacon()) { Plot(Q->GetBeaconPos(), Cyan, 6.f * S); }
    DrawRect(White, Rx - 3.f * S, Ry - 3.f * S, 6.f * S, 6.f * S);

    // touch controls
    if (PC->bTouchUI)
    {
        PC->LayoutButtons();
        for (const FQTTouchButton& B : PC->Buttons)
        {
            const bool bDown = B.Finger >= 0;
            const float R = B.Radius;
            DrawRect(bDown ? FLinearColor(0.3f, 0.95f, 1.f, 0.45f) : FLinearColor(0.02f, 0.01f, 0.08f, 0.55f), B.Center.X - R, B.Center.Y - R, R * 2.f, R * 2.f);
            DrawText(B.Label, White, B.Center.X - B.Label.Len() * 4.f * S, B.Center.Y - 8.f * S, nullptr, 0.8f * S, false);
        }
    }
}
