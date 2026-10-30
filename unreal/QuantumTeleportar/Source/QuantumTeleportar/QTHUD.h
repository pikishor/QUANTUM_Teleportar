#pragma once

#include "CoreMinimal.h"
#include "GameFramework/HUD.h"
#include "QTHUD.generated.h"

// Canvas-drawn HUD (health, coherence, ammo, observation level, radar, touch buttons).
// Replace with UMG once UI art exists; the data it reads (character, game mode, controller) stays the same.
UCLASS()
class QUANTUMTELEPORTAR_API AQTHUD : public AHUD
{
    GENERATED_BODY()

public:
    virtual void DrawHUD() override;
};
