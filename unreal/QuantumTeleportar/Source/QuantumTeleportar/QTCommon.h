#pragma once

#include "CoreMinimal.h"

class UStaticMesh;
class UPrimitiveComponent;
class UMaterialInstanceDynamic;

// Shared tuning constants and helpers. Unreal units are centimetres.
namespace QT
{
    constexpr float BlockPitch = 8000.f;   // distance between road centre lines
    constexpr float RoadWidth = 2000.f;
    constexpr int32 GridN = 8;             // blocks per side
    constexpr float CityHalf = GridN * BlockPitch * 0.5f;
    constexpr float LaneOffset = 500.f;

    // Constructor-only: loads one of the engine's built-in shapes (/Engine/BasicShapes/*).
    UStaticMesh* LoadShape(const TCHAR* Path);

    // Runtime: gives a primitive its own tintable material instance (BasicShapeMaterial "Color").
    UMaterialInstanceDynamic* Tint(UPrimitiveComponent* Comp, const FLinearColor& Color);
}
