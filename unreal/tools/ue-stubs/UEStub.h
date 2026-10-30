// Declaration-only stand-in for the slice of the Unreal Engine API that this module touches.
//
// Purpose: let `g++ -fsyntax-only` catch typos, missing declarations, wrong member names and signature mismatches in OUR code
// without the engine installed (see ../check_syntax.py). Templates such as FMath::Min/Clamp are deliberately strict like the real ones.
//
// This is NOT Unreal. It only knows what the stub author remembered about the engine, so passing this check does not prove the
// code builds against a real engine; it removes the cheap mistakes before a real build.
#pragma once

#include <cmath>
#include <cstdint>
#include <cstddef>
#include <vector>
#include <functional>
#include <type_traits>

typedef int32_t int32;
typedef uint8_t uint8;
typedef uint32_t uint32;
typedef int64_t int64;
typedef wchar_t TCHAR;
#define TEXT(x) L##x
#define PI 3.14159265358979323846

#define UCLASS(...)
#define USTRUCT(...)
#define UENUM(...)
#define UPROPERTY(...)
#define UFUNCTION(...)
#define QUANTUMTELEPORTAR_API
#define SCENE_QUERY_STAT(Name) FName(TEXT(#Name))
#define IMPLEMENT_PRIMARY_GAME_MODULE(Impl, Name, Str)
#define DECLARE_LOG_CATEGORY_EXTERN(Name, A, B) extern int Name
#define DEFINE_LOG_CATEGORY(Name) int Name = 0

class UObject; class AActor; class APawn; class AController; class APlayerController; class UWorld; class UClass;
class UStaticMesh; class UMaterialInterface; class UMaterialInstanceDynamic; class UFont; class UCanvas; class UInputComponent;
class USceneComponent; class UPrimitiveComponent; class UCapsuleComponent; class UCharacterMovementComponent; class AHUD;

// ---- math ---------------------------------------------------------------------------------------
struct FRotator;
struct FVector
{
    double X = 0, Y = 0, Z = 0;
    FVector() {}
    explicit FVector(double V) : X(V), Y(V), Z(V) {}
    FVector(double InX, double InY, double InZ) : X(InX), Y(InY), Z(InZ) {}
    static const FVector ZeroVector, OneVector, UpVector, ForwardVector;
    double Size() const; double SizeSquared() const; double SizeSquared2D() const;
    FVector GetSafeNormal() const;
    FRotator Rotation() const;
    static double Dist2D(const FVector& A, const FVector& B);
    static double Dist(const FVector& A, const FVector& B);
    FVector operator+(const FVector& O) const; FVector operator-(const FVector& O) const; FVector operator-() const;
    FVector operator*(double S) const; FVector operator/(double S) const; FVector operator*(const FVector& O) const;
    FVector& operator+=(const FVector& O); FVector& operator-=(const FVector& O); FVector& operator*=(double S);
};
struct FVector_NetQuantize : FVector {};

struct FVector2D
{
    double X = 0, Y = 0;
    FVector2D() {}
    FVector2D(double InX, double InY) : X(InX), Y(InY) {}
    static const FVector2D ZeroVector;
    double Size() const; FVector2D GetSafeNormal() const;
    static double Distance(const FVector2D& A, const FVector2D& B);
    FVector2D operator+(const FVector2D& O) const; FVector2D operator-(const FVector2D& O) const;
    FVector2D operator*(double S) const; FVector2D operator/(double S) const;
    FVector2D& operator+=(const FVector2D& O);
};

struct FRotator
{
    double Pitch = 0, Yaw = 0, Roll = 0;
    FRotator() {}
    FRotator(double InPitch, double InYaw, double InRoll) : Pitch(InPitch), Yaw(InYaw), Roll(InRoll) {}
    static const FRotator ZeroRotator;
    FVector Vector() const;
};
struct FQuat { static const FQuat Identity; };
struct FTransform
{
    FTransform() {}
    FTransform(const FRotator& Rot, const FVector& Loc = FVector(), const FVector& Scale = FVector(1.0)) {}
    static const FTransform Identity;
};
struct FColor { uint8 R = 0, G = 0, B = 0, A = 255; FColor(uint8 InR, uint8 InG, uint8 InB, uint8 InA = 255) : R(InR), G(InG), B(InB), A(InA) {} };
struct FLinearColor
{
    float R = 0, G = 0, B = 0, A = 1;
    FLinearColor() {}
    FLinearColor(float InR, float InG, float InB, float InA = 1.f) : R(InR), G(InG), B(InB), A(InA) {}
    FColor ToFColor(bool bSRGB) const;
};

struct FMath
{
    template <class T> static T Min(const T A, const T B);
    template <class T> static T Max(const T A, const T B);
    template <class T> static T Clamp(const T X, const T Lo, const T Hi);
    template <class T> static T Abs(const T A);
    static float Sin(float V); static float Cos(float V); static float Sqrt(float V);
    static float FRand(); static float FRandRange(float A, float B); static int32 RandRange(int32 A, int32 B); static bool RandBool();
    static FVector VRandCone(const FVector& Dir, float ConeHalfAngleRad);
    static int32 FloorToInt(float V); static int32 CeilToInt(float V); static int32 RoundToInt(float V); static float RoundToFloat(float V);
    static float FInterpTo(float Current, float Target, float DeltaTime, float Speed);
    static FRotator RInterpTo(const FRotator& Current, const FRotator& Target, float DeltaTime, float Speed);
    template <class T> static auto DegreesToRadians(T const& Deg) -> T;
};

struct FRandomStream { explicit FRandomStream(int32 Seed); float FRand() const; int32 RandRange(int32 A, int32 B) const; };

// ---- containers / strings -----------------------------------------------------------------------
struct FName
{
    FName() {}
    FName(const TCHAR* Str) {}
    bool operator==(const FName& O) const; bool operator==(const TCHAR* O) const;
};
struct FString
{
    FString() {}
    FString(const TCHAR* Str) {}
    int32 Len() const;
    FString& operator+=(const TCHAR* S);
    const TCHAR* operator*() const;
    static FString Printf(const TCHAR* Fmt, ...);
};

template <class T> struct TArray : std::vector<T>
{
    int32 Num() const { return static_cast<int32>(this->size()); }
    void Reset() { this->clear(); }
    T& Add(const T& V) { this->push_back(V); return this->back(); }
    void RemoveAtSwap(int32 Index);
    void Swap(int32 A, int32 B);
    template <class P> T* FindByPredicate(P Pred) { return nullptr; }
    T& AddDefaulted_GetRef();
};

template <class T> struct TWeakObjectPtr
{
    TWeakObjectPtr() {}
    TWeakObjectPtr(T* Obj) {}
    TWeakObjectPtr& operator=(T* Obj); TWeakObjectPtr& operator=(std::nullptr_t);
    T* Get() const; bool IsValid() const; T* operator->() const;
};
template <class T> struct TSubclassOf { TSubclassOf() {} TSubclassOf(UClass* C) {} };

// ---- core objects -------------------------------------------------------------------------------
class UClass {};
class UObject
{
public:
    virtual ~UObject() {}
    UWorld* GetWorld() const;
    template <class T> bool IsA() const;
    template <class T> T* CreateDefaultSubobject(const FName& Name);
};
template <class T, class U> T* Cast(U* Obj) { return dynamic_cast<T*>(Obj); }
template <class T> T* NewObject(UObject* Outer);

struct FActorTickFunction { bool bCanEverTick = false; };
struct FActorComponentTickFunction { bool bCanEverTick = false; };
enum ELevelTick { LEVELTICK_All };
namespace ECollisionEnabled { enum Type { NoCollision, QueryOnly, PhysicsOnly, QueryAndPhysics }; }
namespace EComponentMobility { enum Type { Static, Stationary, Movable }; }
enum ECollisionChannel { ECC_WorldStatic, ECC_WorldDynamic, ECC_Pawn, ECC_Visibility };
enum class ESpawnActorCollisionHandlingMethod : uint8 { Undefined, AlwaysSpawn, AdjustIfPossibleButAlwaysSpawn };
namespace ETouchIndex { enum Type { Touch1, Touch2, Touch3 }; }
enum EInputEvent { IE_Pressed, IE_Released, IE_Repeat };
struct FAttachmentTransformRules { static const FAttachmentTransformRules KeepRelativeTransform; };
struct FDamageEvent {};
class UDamageType : public UObject { public: static UClass* StaticClass(); };

struct FCollisionQueryParams { FCollisionQueryParams(const FName& Tag, bool bComplex, const AActor* Ignore = nullptr) {} void AddIgnoredActor(const AActor* A); };
struct FCollisionShape { static FCollisionShape MakeSphere(float Radius); };
struct FHitResult { FVector_NetQuantize ImpactPoint; AActor* GetActor() const; };
struct FActorSpawnParameters { AActor* Owner = nullptr; ESpawnActorCollisionHandlingMethod SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::Undefined; };

struct FKey {};
struct EKeys { static const FKey W, S, A, D, Up, Down, Left, Right, LeftMouseButton, RightMouseButton, LeftShift, SpaceBar, Q, E, G, R; };
struct FInputModeDataBase {};
struct FInputModeGameOnly : FInputModeDataBase {};

struct FTimerHandle {};
struct FTimerDelegate { template <class F> static FTimerDelegate CreateLambda(F&& Fn) { return FTimerDelegate(); } };
struct FTimerManager
{
    template <class U> void SetTimer(FTimerHandle& H, U* Obj, void (U::*Func)(), float Rate, bool bLoop);
    void SetTimer(FTimerHandle& H, const FTimerDelegate& D, float Rate, bool bLoop);
};

// ---- components ---------------------------------------------------------------------------------
class UActorComponent : public UObject
{
public:
    FActorComponentTickFunction PrimaryComponentTick;
    virtual void TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction);
    AActor* GetOwner() const;
    void RegisterComponent();
};
class USceneComponent : public UActorComponent
{
public:
    void SetupAttachment(USceneComponent* Parent, const FName& Socket = FName());
    void SetRelativeLocation(const FVector& V); void SetRelativeScale3D(const FVector& V);
    void AddLocalRotation(const FRotator& R);
    void SetMobility(EComponentMobility::Type M);
    bool AttachToComponent(USceneComponent* Parent, const FAttachmentTransformRules& Rules, const FName& Socket = FName());
};
template <class Sig> struct TMulticastDelegate;
struct FHitDelegate { template <class U, class F> void AddDynamic(U* Obj, F Func); };
struct FOverlapDelegate { template <class U, class F> void AddDynamic(U* Obj, F Func); };
class UPrimitiveComponent : public USceneComponent
{
public:
    void SetCollisionProfileName(const FName& Name);
    void SetCollisionEnabled(ECollisionEnabled::Type T);
    void SetGenerateOverlapEvents(bool b);
    void IgnoreActorWhenMoving(AActor* Actor, bool bShouldIgnore);
    UMaterialInstanceDynamic* CreateAndSetMaterialInstanceDynamic(int32 Index);
    FHitDelegate OnComponentHit; FOverlapDelegate OnComponentBeginOverlap;
};
class UStaticMeshComponent : public UPrimitiveComponent { public: bool SetStaticMesh(UStaticMesh* M); };
class UInstancedStaticMeshComponent : public UStaticMeshComponent { public: int32 AddInstance(const FTransform& T, bool bWorldSpace = false); };
class USphereComponent : public UPrimitiveComponent { public: void InitSphereRadius(float R); };
class UCapsuleComponent : public UPrimitiveComponent { public: float GetScaledCapsuleHalfHeight() const; };
class UStaticMesh : public UObject {};
class UMaterialInterface : public UObject {};
class UMaterialInstanceDynamic : public UMaterialInterface { public: void SetVectorParameterValue(const FName& Name, const FLinearColor& V); };
class UProjectileMovementComponent : public UActorComponent { public: float ProjectileGravityScale = 1, InitialSpeed = 0, MaxSpeed = 0; FVector Velocity; };
class USpringArmComponent : public USceneComponent { public: float TargetArmLength = 0; FVector SocketOffset; bool bUsePawnControlRotation = false; static const FName SocketName; };
class UCameraComponent : public USceneComponent { public: float FieldOfView = 90; void SetFieldOfView(float F); };
class UCharacterMovementComponent : public UActorComponent { public: bool bOrientRotationToMovement = false; float MaxWalkSpeed = 0, JumpZVelocity = 0, AirControl = 0; };
class ULightComponent : public USceneComponent { public: void SetIntensity(float I); void SetLightColor(FLinearColor C, bool bSRGB = true); };
class USkyLightComponent : public ULightComponent { public: void RecaptureSky(); };
class UDirectionalLightComponent : public ULightComponent {};
class UExponentialHeightFogComponent : public USceneComponent { public: void SetFogDensity(float D); void SetFogInscatteringColor(FLinearColor C); };
class UInputComponent : public UActorComponent
{
public:
    template <class U> void BindTouch(EInputEvent Event, U* Obj, void (U::*Func)(ETouchIndex::Type, FVector));
};

// ---- actors -------------------------------------------------------------------------------------
class AActor : public UObject
{
public:
    AActor();
    FActorTickFunction PrimaryActorTick;
    float InitialLifeSpan = 0;
    USceneComponent* RootComponent = nullptr;
    virtual void BeginPlay();
    virtual void Tick(float DeltaSeconds);
    virtual float TakeDamage(float DamageAmount, struct FDamageEvent const& DamageEvent, AController* EventInstigator, AActor* DamageCauser);
    FVector GetActorLocation() const; FRotator GetActorRotation() const; FTransform GetActorTransform() const;
    FVector GetActorForwardVector() const; FVector GetActorRightVector() const; FVector GetVelocity() const;
    bool SetActorLocation(const FVector& NewLocation, bool bSweep = false, FHitResult* OutSweepHitResult = nullptr);
    void SetActorRotation(const FRotator& R); void SetActorScale3D(const FVector& S);
    USceneComponent* GetRootComponent() const; void SetRootComponent(USceneComponent* C);
    bool Destroy(); AActor* GetOwner() const;
    bool TeleportTo(const FVector& Dest, const FRotator& Rot, bool bIsATest = false, bool bNoCheck = false);
    FTimerManager& GetWorldTimerManager() const;
    void FinishSpawning(const FTransform& T);
};
class AController : public AActor
{
public:
    void GetPlayerViewPoint(FVector& Loc, FRotator& Rot) const;
    void SetControlRotation(const FRotator& R); FRotator GetControlRotation() const; APawn* GetPawn() const;
};
class APawn : public AActor
{
public:
    AController* GetController() const;
    void AddMovementInput(FVector Dir, float Scale = 1.f, bool bForce = false);
    void AddControllerYawInput(float V); void AddControllerPitchInput(float V);
    bool bUseControllerRotationYaw = false;
};
class ACharacter : public APawn
{
public:
    UCapsuleComponent* GetCapsuleComponent() const; UCharacterMovementComponent* GetCharacterMovement() const; void Jump();
};
class APlayerCameraManager : public AActor { public: float ViewPitchMin = 0, ViewPitchMax = 0; };
class APlayerController : public AController
{
public:
    virtual void BeginPlay(); virtual void SetupInputComponent(); virtual void PlayerTick(float DeltaTime);
    UInputComponent* InputComponent = nullptr; APlayerCameraManager* PlayerCameraManager = nullptr; bool bShowMouseCursor = false;
    void SetInputMode(const FInputModeDataBase& M); void GetViewportSize(int32& X, int32& Y) const;
    bool IsInputKeyDown(FKey K) const; bool WasInputKeyJustPressed(FKey K) const; void GetInputMouseDelta(float& DX, float& DY) const;
    void AddYawInput(float V); void AddPitchInput(float V);
};
class UFont : public UObject {};
class UCanvas : public UObject { public: float ClipX = 0, ClipY = 0; };
class AHUD : public AActor
{
public:
    UCanvas* Canvas = nullptr;
    virtual void DrawHUD();
    void DrawRect(FLinearColor C, float X, float Y, float W, float H);
    void DrawLine(float X1, float Y1, float X2, float Y2, FLinearColor C, float Thickness = 0.f);
    void DrawText(const FString& Text, FLinearColor C, float X, float Y, UFont* Font = nullptr, float Scale = 1.f, bool bScalePosition = false);
    APawn* GetOwningPawn() const; APlayerController* GetOwningPlayerController() const;
};
class AGameModeBase : public AActor
{
public:
    TSubclassOf<APawn> DefaultPawnClass; TSubclassOf<APlayerController> PlayerControllerClass; TSubclassOf<AHUD> HUDClass;
    virtual void HandleStartingNewPlayer_Implementation(APlayerController* NewPlayer);
};
class ALight : public AActor { public: ULightComponent* GetLightComponent() const; };
class ADirectionalLight : public ALight {};
class ASkyLight : public AActor { public: USkyLightComponent* GetLightComponent() const; };
class AExponentialHeightFog : public AActor { public: UExponentialHeightFogComponent* GetComponent() const; };

// ---- world / statics ----------------------------------------------------------------------------
class UWorld : public UObject
{
public:
    template <class T> T* GetAuthGameMode() const;
    template <class T> T* SpawnActor(UClass* Class, const FTransform& Transform, const FActorSpawnParameters& P = FActorSpawnParameters());
    template <class T> T* SpawnActor(const FVector& Loc, const FRotator& Rot, const FActorSpawnParameters& P = FActorSpawnParameters());
    template <class T> T* SpawnActor(UClass* Class, const FVector& Loc, const FRotator& Rot, const FActorSpawnParameters& P = FActorSpawnParameters());
    template <class T> T* SpawnActorDeferred(UClass* Class, const FTransform& Xf, AActor* Owner = nullptr, APawn* Instigator = nullptr,
                                             ESpawnActorCollisionHandlingMethod Method = ESpawnActorCollisionHandlingMethod::Undefined);
    bool LineTraceSingleByChannel(FHitResult& Out, const FVector& Start, const FVector& End, ECollisionChannel Ch,
                                  const FCollisionQueryParams& P = FCollisionQueryParams(FName(), false)) const;
    bool SweepSingleByChannel(FHitResult& Out, const FVector& Start, const FVector& End, const FQuat& Rot, ECollisionChannel Ch,
                              const FCollisionShape& Shape, const FCollisionQueryParams& P = FCollisionQueryParams(FName(), false)) const;
    float GetTimeSeconds() const;
};
template <class T> struct TActorIterator
{
    explicit TActorIterator(UWorld* W);
    explicit operator bool() const; TActorIterator& operator++(); T* operator*() const; T* operator->() const;
};
struct UGameplayStatics
{
    static APawn* GetPlayerPawn(const UObject* Ctx, int32 Index);
    static float ApplyPointDamage(AActor* Damaged, float Base, const FVector& FromDir, const FHitResult& Hit, AController* Instigator,
                                  AActor* Causer, TSubclassOf<UDamageType> Type);
    static float ApplyDamage(AActor* Damaged, float Base, AController* Instigator, AActor* Causer, TSubclassOf<UDamageType> Type);
    static bool ApplyRadialDamage(const UObject* Ctx, float Base, const FVector& Origin, float Radius, TSubclassOf<UDamageType> Type,
                                  const TArray<AActor*>& Ignore, AActor* Causer = nullptr, AController* Instigator = nullptr,
                                  bool bFull = false, ECollisionChannel Ch = ECC_Visibility);
    static void OpenLevel(const UObject* Ctx, FName Level, bool bAbsolute = true, FString Options = FString());
    static FString GetCurrentLevelName(const UObject* Ctx, bool bRemovePrefix = true);
};
namespace ConstructorHelpers
{
    template <class T> struct FObjectFinder { explicit FObjectFinder(const TCHAR* Path); bool Succeeded() const; T* Object = nullptr; };
}

void DrawDebugLine(const UWorld* W, const FVector& Start, const FVector& End, const FColor& C, bool bPersistent = false, float Life = -1.f, uint8 Depth = 0, float Thickness = 0.f);
void DrawDebugSphere(const UWorld* W, const FVector& Center, float Radius, int32 Segments, const FColor& C, bool bPersistent = false, float Life = -1.f, uint8 Depth = 0, float Thickness = 0.f);
void DrawDebugCylinder(const UWorld* W, const FVector& Start, const FVector& End, float Radius, int32 Segments, const FColor& C, bool bPersistent = false, float Life = -1.f, uint8 Depth = 0, float Thickness = 0.f);
