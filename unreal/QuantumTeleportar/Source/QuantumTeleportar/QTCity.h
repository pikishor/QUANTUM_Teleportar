#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "QTCity.generated.h"

class UInstancedStaticMeshComponent;
class UStaticMesh;

// Procedural graybox city (8x8 blocks) built from engine primitives, so the project runs with zero authored art.
// Replace with the real level and meshes once art lands; gameplay only needs RandomRoadPoint/Intersections.
UCLASS()
class QUANTUMTELEPORTAR_API AQTCity : public AActor
{
    GENERATED_BODY()

public:
    AQTCity();

    /** Random point on a road at ground level. */
    FVector RandomRoadPoint() const;
    /** Road point between RMin and RMax centimetres from Center (snaps a ring sample onto the nearest road). */
    bool RoadPointNear(const FVector& Center, float RMin, float RMax, FVector& Out) const;

    TArray<FVector> Intersections;

protected:
    virtual void BeginPlay() override;

private:
    UInstancedStaticMeshComponent* MakeISM(const FLinearColor& Color, bool bCollide);

    UPROPERTY() UStaticMesh* CubeMesh = nullptr;
};
