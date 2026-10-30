#include "QTCity.h"
#include "QTCommon.h"
#include "Components/InstancedStaticMeshComponent.h"
#include "Engine/StaticMesh.h"

AQTCity::AQTCity()
{
    PrimaryActorTick.bCanEverTick = false;
    SetRootComponent(CreateDefaultSubobject<USceneComponent>(TEXT("Root")));
    CubeMesh = QT::LoadShape(TEXT("/Engine/BasicShapes/Cube.Cube"));
}

UInstancedStaticMeshComponent* AQTCity::MakeISM(const FLinearColor& Color, bool bCollide)
{
    UInstancedStaticMeshComponent* Comp = NewObject<UInstancedStaticMeshComponent>(this);
    Comp->SetStaticMesh(CubeMesh);
    Comp->SetMobility(EComponentMobility::Movable);
    if (bCollide)
    {
        Comp->SetCollisionProfileName(TEXT("BlockAll"));
    }
    else
    {
        Comp->SetCollisionEnabled(ECollisionEnabled::NoCollision);
    }
    Comp->RegisterComponent();
    Comp->AttachToComponent(GetRootComponent(), FAttachmentTransformRules::KeepRelativeTransform);
    QT::Tint(Comp, Color);
    return Comp;
}

void AQTCity::BeginPlay()
{
    Super::BeginPlay();
    using namespace QT;

    FRandomStream Rng(2025);
    const float L = 2.f * CityHalf + RoadWidth;

    // Ground (top face at z = 0) and road surfaces; the unit cube is 100 cm, so scale = size / 100.
    UInstancedStaticMeshComponent* Ground = MakeISM(FLinearColor(0.02f, 0.02f, 0.05f), true);
    Ground->AddInstance(FTransform(FRotator::ZeroRotator, FVector(0.f, 0.f, -50.f), FVector(600.f, 600.f, 1.f)));

    UInstancedStaticMeshComponent* Roads = MakeISM(FLinearColor(0.04f, 0.04f, 0.07f), false);
    UInstancedStaticMeshComponent* Dashes = MakeISM(FLinearColor(0.8f, 0.78f, 1.f), false);
    for (int32 i = 0; i <= GridN; ++i)
    {
        const float C = -CityHalf + i * BlockPitch;
        Roads->AddInstance(FTransform(FRotator::ZeroRotator, FVector(0.f, C, 2.f), FVector(L / 100.f, RoadWidth / 100.f, 0.04f)));
        Roads->AddInstance(FTransform(FRotator::ZeroRotator, FVector(C, 0.f, 2.f), FVector(RoadWidth / 100.f, L / 100.f, 0.04f)));
        for (float U = -CityHalf + 500.f; U < CityHalf; U += 1000.f)
        {
            bool bNearJunction = false;
            for (int32 k = 0; k <= GridN; ++k)
            {
                if (FMath::Abs(U - (-CityHalf + k * BlockPitch)) < RoadWidth * 0.5f + 150.f) { bNearJunction = true; break; }
            }
            if (bNearJunction) { continue; }
            Dashes->AddInstance(FTransform(FRotator::ZeroRotator, FVector(U, C, 5.f), FVector(4.5f, 0.35f, 0.02f)));
            Dashes->AddInstance(FTransform(FRotator::ZeroRotator, FVector(C, U, 5.f), FVector(0.35f, 4.5f, 0.02f)));
        }
    }

    // Buildings: four lots per block, taller toward the centre. Neon trims are placeholders until real materials exist.
    static const float Foot[2] = { 1800.f, 2600.f };
    static const float Heights[5] = { 1600.f, 2800.f, 4400.f, 6200.f, 8800.f };
    const FLinearColor Tints[3] = { FLinearColor(0.10f, 0.12f, 0.30f), FLinearColor(0.20f, 0.10f, 0.32f), FLinearColor(0.08f, 0.22f, 0.30f) };
    UInstancedStaticMeshComponent* Buildings[3];
    for (int32 k = 0; k < 3; ++k)
    {
        Buildings[k] = MakeISM(Tints[k], true);
    }
    UInstancedStaticMeshComponent* Trims[2] = { MakeISM(FLinearColor(0.2f, 1.f, 1.f), false), MakeISM(FLinearColor(1.f, 0.2f, 0.9f), false) };

    for (int32 i = 0; i < GridN; ++i)
    {
        for (int32 j = 0; j < GridN; ++j)
        {
            const float Bx = -CityHalf + (i + 0.5f) * BlockPitch, By = -CityHalf + (j + 0.5f) * BlockPitch;
            const float Central = 1.f - FMath::Min(1.f, static_cast<float>(FVector2D(Bx, By).Size()) / (CityHalf * 1.1f));
            for (int32 Sx = -1; Sx <= 1; Sx += 2)
            {
                for (int32 Sy = -1; Sy <= 1; Sy += 2)
                {
                    if (Rng.FRand() < 0.1f) { continue; }   // plaza
                    const float W = Foot[Rng.FRand() < 0.5f ? 0 : 1], D = Foot[Rng.FRand() < 0.5f ? 0 : 1];
                    const int32 Hi = FMath::Clamp(FMath::FloorToInt(Rng.FRand() * 2.f + Central * 3.4f), 0, 4);
                    const float H = Heights[Hi];
                    const FVector Centre(Bx + Sx * 1500.f, By + Sy * 1500.f, H * 0.5f);
                    Buildings[Rng.RandRange(0, 2)]->AddInstance(FTransform(FRotator::ZeroRotator, Centre, FVector(W / 100.f, D / 100.f, H / 100.f)));
                    Trims[Rng.RandRange(0, 1)]->AddInstance(FTransform(FRotator::ZeroRotator, FVector(Centre.X, Centre.Y, H + 30.f), FVector((W + 60.f) / 100.f, (D + 60.f) / 100.f, 0.6f)));
                }
            }
        }
    }

    for (int32 i = 1; i < GridN; ++i)
    {
        for (int32 j = 1; j < GridN; ++j)
        {
            Intersections.Add(FVector(-CityHalf + i * BlockPitch, -CityHalf + j * BlockPitch, 0.f));
        }
    }
}

FVector AQTCity::RandomRoadPoint() const
{
    using namespace QT;
    const float C = -CityHalf + FMath::RandRange(0, GridN) * BlockPitch;
    const float U = FMath::FRandRange(-1.f, 1.f) * (CityHalf - 1200.f);
    const float O = FMath::FRandRange(-700.f, 700.f);
    return FMath::RandBool() ? FVector(U, C + O, 0.f) : FVector(C + O, U, 0.f);
}

bool AQTCity::RoadPointNear(const FVector& Center, float RMin, float RMax, FVector& Out) const
{
    using namespace QT;
    auto Snap = [](float V)
    {
        const float Index = FMath::Clamp(FMath::RoundToFloat((V + CityHalf) / BlockPitch), 0.f, static_cast<float>(GridN));
        return -CityHalf + Index * BlockPitch + FMath::FRandRange(-700.f, 700.f);
    };
    for (int32 Try = 0; Try < 10; ++Try)
    {
        const float A = FMath::FRandRange(0.f, 2.f * PI), R = FMath::FRandRange(RMin, RMax);
        float X = Center.X + FMath::Cos(A) * R, Y = Center.Y + FMath::Sin(A) * R;
        if (FMath::RandBool()) { X = Snap(X); } else { Y = Snap(Y); }
        const double D = FVector2D::Distance(FVector2D(X, Y), FVector2D(Center.X, Center.Y));
        if (D >= RMin && D <= RMax && FMath::Abs(X) < CityHalf - 800.f && FMath::Abs(Y) < CityHalf - 800.f)
        {
            Out = FVector(X, Y, 0.f);
            return true;
        }
    }
    return false;
}
