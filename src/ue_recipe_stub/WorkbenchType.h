#pragma once

#include "CoreMinimal.h"
#include "Engine/DataAsset.h"
#include "WorkbenchType.generated.h"

/**
 * Workbench type — matches /Script/Vein.WorkbenchType
 * Data-mined from VEIN game assets via FModel
 */
UCLASS(BlueprintType)
class VEIN_API UWorkbenchType : public UDataAsset
{
	GENERATED_BODY()

public:
	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	FText Name;

	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	TArray<UWorkbenchType*> LowerWorkbenches;

	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	bool bHasThreeTools = false;

	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	bool bHasFluidSlot = false;

	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	bool bHasTwoFluidSlots = false;
};
