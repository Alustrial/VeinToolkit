#pragma once

#include "CoreMinimal.h"
#include "Engine/DataAsset.h"
#include "RecipeType.generated.h"

/**
 * Recipe category type — matches /Script/Vein.RecipeType
 * Data-mined from VEIN game assets via FModel
 */
UCLASS(BlueprintType)
class VEIN_API URecipeType : public UDataAsset
{
	GENERATED_BODY()

public:
	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	FText Name;

	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	UTexture2D* Icon = nullptr;

	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	FLinearColor Color = FLinearColor::White;

	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	int32 order = 0;
};
