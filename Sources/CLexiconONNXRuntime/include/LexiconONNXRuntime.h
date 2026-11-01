#pragma once

#include <stddef.h>
#include <stdint.h>

#include "onnxruntime_c_api.h"

typedef void *LexiconONNXRuntimeSessionRef;

const char *LexiconONNXRuntimeVersion(void);

int LexiconONNXRuntimeCreateSession(
	const char *modelPath,
	LexiconONNXRuntimeSessionRef *session,
	char **error
);

void LexiconONNXRuntimeReleaseSession(LexiconONNXRuntimeSessionRef session);

int LexiconONNXRuntimeRun(
	LexiconONNXRuntimeSessionRef session,
	const char *const *inputNames,
	const int64_t *const *inputData,
	size_t inputCount,
	const int64_t *shape,
	size_t shapeCount,
	const char *outputName,
	float **outputValues,
	size_t *outputValueCount,
	int64_t **outputShape,
	size_t *outputShapeCount,
	char **error
);

void LexiconONNXRuntimeReleaseTensor(float *outputValues, int64_t *outputShape);
void LexiconONNXRuntimeReleaseError(char *error);
