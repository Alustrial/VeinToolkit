#pragma once

#include "CoreMinimal.h"
#include "Engine/DataAsset.h"
#include "RecipeType.h"
#include "WorkbenchType.h"
#include "BaseRecipe.generated.h"

/**
 * Item + quantity entry — the REAL VEIN shared struct used for BOTH recipe
 * ingredients and recipe results. Name MUST be FItemWithQuantity (serializes as
 * "ItemWithQuantity") to match VEIN's BaseRecipe. Confirmed via game log struct-tag
 * mismatch: tag RecipeIngredient/RecipeResult != prop ItemWithQuantity.
 */
USTRUCT(BlueprintType)
struct FItemWithQuantity
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	TSubclassOf<AActor> Item;

	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	int32 Quantity = 1;
};

/**
 * A possible set of ingredients for a recipe (one recipe can have multiple sets)
 */
USTRUCT(BlueprintType)
struct FPossibleIngredientSet
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	TArray<FItemWithQuantity> Ingredients;

	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	TArray<FName> IngredientTags;

	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	TArray<TSubclassOf<AActor>> ToolObjects;

	// REAL VEIN: Fluids is a MAP, not an Array (game log: Fluids Previous(ArrayProperty) Current(MapProperty)).
	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	TMap<TSubclassOf<AActor>, int32> Fluids;

	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	bool bOnlyOneToolNeeded = false;

	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	UWorkbenchType* WorkbenchType = nullptr;

	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	bool bEnabled = true;

	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	bool bNoCookedItems = false;
};

/**
 * Base recipe class — matches /Script/Vein.BaseRecipe
 * Data-mined from VEIN game assets via FModel
 *
 * UPrimaryDataAsset (NOT plain UDataAsset) so the cooked asset registers as a
 * PRIMARY asset of type "Recipe" — which is exactly what VeinAssetManager's
 * GetAllRecipes() queries (registry keys are "Recipe:CR_X"). A plain UDataAsset
 * is not a primary asset and would never be discovered. GetPrimaryAssetId is
 * overridden to type "Recipe" to match VEIN's key format.
 */
UCLASS(BlueprintType)
class VEIN_API UBaseRecipe : public UPrimaryDataAsset
{
	GENERATED_BODY()

public:
	// Make this a "Recipe" primary asset (matches VEIN's "Recipe:<name>" registry keys)
	virtual FPrimaryAssetId GetPrimaryAssetId() const override
	{
		return FPrimaryAssetId(FPrimaryAssetType(TEXT("Recipe")), GetFName());
	}

	// --- Core ---

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Recipe")
	FText RecipeName;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Recipe")
	FText RecipeFlavorText;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Recipe")
	URecipeType* RecipeType = nullptr;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Recipe")
	bool bEnabled = true;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Recipe")
	bool bDefaultUnlocked = true;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Recipe")
	double CraftTime = 5.0;

	// --- Ingredients & Results ---

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Crafting")
	TArray<FPossibleIngredientSet> PossibleIngredients;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Crafting")
	TArray<FItemWithQuantity> Results;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Crafting")
	TMap<TSubclassOf<AActor>, int32> ResultFluids;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Crafting")
	TArray<UWorkbenchType*> ValidWorkbenches;

	// --- Audio ---

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Audio")
	USoundBase* CraftSound = nullptr;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Audio")
	USoundBase* CraftLoopSound = nullptr;

	// --- XP & Stats ---

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Progression")
	TMap<TSubclassOf<UObject>, double> CraftingRewardXP;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Progression")
	TMap<TSubclassOf<UObject>, double> CookingRewardXP;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Progression")
	TMap<TSubclassOf<UObject>, double> StatRequirements;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Progression")
	TMap<TSubclassOf<UObject>, int32> SchematicSkipLevel;

	// --- Cooking ---

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Cooking")
	double CookLimit = 0.0;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Cooking")
	TSubclassOf<UObject> CookLimitOverride;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Cooking")
	double MinimumHeatToCraft = 0.0;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Cooking")
	bool bDontApplyCookedModifier = false;

	// --- Scent ---

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Scent")
	double ScentStrength = 0.0;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Scent")
	double ScentRadius = 0.0;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Scent")
	double ScentStrengthBurning = 0.0;

	// --- Icon Overrides ---

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "UI")
	TSoftObjectPtr<UStaticMesh> IconOverrideMesh;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "UI")
	TSoftObjectPtr<UTexture2D> IconOverrideThumbnail;

	// --- Item Overrides ---

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "ItemOverride")
	FText ItemPrefix;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "ItemOverride")
	FText ItemOverrideName;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "ItemOverride")
	FText ItemOverrideDescription;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "ItemOverride")
	bool bOneToOneResultItem = false;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "ItemOverride")
	bool ItemData = false;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "ItemOverride")
	bool ItemDataIgnoreItemClass = false;
};
