#include "QTCommon.h"
#include "Components/PrimitiveComponent.h"
#include "Engine/StaticMesh.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "UObject/ConstructorHelpers.h"

UStaticMesh* QT::LoadShape(const TCHAR* Path)
{
    ConstructorHelpers::FObjectFinder<UStaticMesh> Finder(Path);
    return Finder.Succeeded() ? Finder.Object : nullptr;
}

UMaterialInstanceDynamic* QT::Tint(UPrimitiveComponent* Comp, const FLinearColor& Color)
{
    UMaterialInstanceDynamic* Mid = Comp ? Comp->CreateAndSetMaterialInstanceDynamic(0) : nullptr;
    if (Mid)
    {
        Mid->SetVectorParameterValue(TEXT("Color"), Color);
    }
    return Mid;
}
