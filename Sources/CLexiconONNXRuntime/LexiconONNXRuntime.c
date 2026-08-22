#include "LexiconONNXRuntime.h"

#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
#else
#include <dlfcn.h>
#endif

#ifndef LEXICON_ONNX_RUNTIME_LIBRARY_PATH
#if defined(_WIN32)
#define LEXICON_ONNX_RUNTIME_LIBRARY_PATH "onnxruntime.dll"
#else
#define LEXICON_ONNX_RUNTIME_LIBRARY_PATH "libonnxruntime.so"
#endif
#endif

static void LexiconONNXRuntimeSetError(char **error, const char *message) {
	if (error == NULL) {
		return;
	}
	if (message == NULL) {
		message = "unknown ONNX Runtime error";
	}
	size_t length = strlen(message);
	char *copy = (char *)malloc(length + 1);
	if (copy == NULL) {
		*error = NULL;
		return;
	}
	memcpy(copy, message, length + 1);
	*error = copy;
}

#if __has_include("onnxruntime_c_api.h")

typedef struct LexiconONNXRuntimeSession {
	const OrtApi *api;
	OrtEnv *env;
	OrtSession *session;
} LexiconONNXRuntimeSession;

typedef const OrtApiBase *(ORT_API_CALL *LexiconONNXRuntimeGetApiBaseFunction)(void);

static const OrtApiBase *LexiconONNXRuntimeGetApiBase(char **error) {
	static LexiconONNXRuntimeGetApiBaseFunction function = NULL;
	if (function != NULL) {
		return function();
	}
#if defined(_WIN32)
	HMODULE handle = LoadLibraryA(LEXICON_ONNX_RUNTIME_LIBRARY_PATH);
	if (handle == NULL) {
		handle = LoadLibraryA("onnxruntime.dll");
	}
	if (handle == NULL) {
		LexiconONNXRuntimeSetError(error, "Could not load onnxruntime.dll.");
		return NULL;
	}
	function = (LexiconONNXRuntimeGetApiBaseFunction)GetProcAddress(handle, "OrtGetApiBase");
#else
	void *handle = dlopen(LEXICON_ONNX_RUNTIME_LIBRARY_PATH, RTLD_NOW | RTLD_LOCAL);
	if (handle == NULL) {
		handle = dlopen("libonnxruntime.so", RTLD_NOW | RTLD_LOCAL);
	}
	if (handle == NULL) {
		handle = dlopen("libonnxruntime.so.1", RTLD_NOW | RTLD_LOCAL);
	}
	if (handle == NULL) {
		LexiconONNXRuntimeSetError(error, dlerror());
		return NULL;
	}
	function = (LexiconONNXRuntimeGetApiBaseFunction)dlsym(handle, "OrtGetApiBase");
#endif
	if (function == NULL) {
		LexiconONNXRuntimeSetError(error, "Could not load ONNX Runtime OrtGetApiBase symbol.");
		return NULL;
	}
	return function();
}

static int LexiconONNXRuntimeCheck(const OrtApi *api, OrtStatus *status, char **error) {
	if (status == NULL) {
		return 1;
	}
	const char *message = api->GetErrorMessage(status);
	LexiconONNXRuntimeSetError(error, message);
	api->ReleaseStatus(status);
	return 0;
}

static size_t LexiconONNXRuntimeElementCount(const int64_t *shape, size_t shapeCount) {
	size_t count = 1;
	for (size_t index = 0; index < shapeCount; ++index) {
		if (shape[index] <= 0) {
			return 0;
		}
		count *= (size_t)shape[index];
	}
	return count;
}

const char *LexiconONNXRuntimeVersion(void) {
	const OrtApiBase *base = LexiconONNXRuntimeGetApiBase(NULL);
	if (base == NULL) {
		return "unknown";
	}
	return base->GetVersionString();
}

int LexiconONNXRuntimeCreateSession(
	const char *modelPath,
	LexiconONNXRuntimeSessionRef *session,
	char **error
) {
	if (session == NULL) {
		LexiconONNXRuntimeSetError(error, "Missing ONNX Runtime session output pointer.");
		return 0;
	}
	*session = NULL;
	const OrtApiBase *base = LexiconONNXRuntimeGetApiBase(error);
	if (base == NULL) {
		return 0;
	}
	const OrtApi *api = base->GetApi(ORT_API_VERSION);
	if (api == NULL) {
		LexiconONNXRuntimeSetError(error, "ONNX Runtime API version is not available.");
		return 0;
	}

	LexiconONNXRuntimeSession *created = (LexiconONNXRuntimeSession *)calloc(1, sizeof(LexiconONNXRuntimeSession));
	if (created == NULL) {
		LexiconONNXRuntimeSetError(error, "Could not allocate ONNX Runtime session.");
		return 0;
	}
	created->api = api;

	OrtSessionOptions *options = NULL;
	if (!LexiconONNXRuntimeCheck(api, api->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "Lexicon", &created->env), error)
		|| !LexiconONNXRuntimeCheck(api, api->CreateSessionOptions(&options), error)
		|| !LexiconONNXRuntimeCheck(api, api->SetSessionGraphOptimizationLevel(options, ORT_ENABLE_BASIC), error)) {
		if (options != NULL) {
			api->ReleaseSessionOptions(options);
		}
		LexiconONNXRuntimeReleaseSession((LexiconONNXRuntimeSessionRef)created);
		return 0;
	}

#if defined(_WIN32)
	api->ReleaseSessionOptions(options);
	LexiconONNXRuntimeReleaseSession((LexiconONNXRuntimeSessionRef)created);
	LexiconONNXRuntimeSetError(error, "Windows ONNX Runtime session path support needs ORTCHAR_T wide string bridging.");
	return 0;
#else
	int ok = LexiconONNXRuntimeCheck(api, api->CreateSession(created->env, modelPath, options, &created->session), error);
	api->ReleaseSessionOptions(options);
	if (!ok) {
		LexiconONNXRuntimeReleaseSession((LexiconONNXRuntimeSessionRef)created);
		return 0;
	}
	*session = (LexiconONNXRuntimeSessionRef)created;
	return 1;
#endif
}

void LexiconONNXRuntimeReleaseSession(LexiconONNXRuntimeSessionRef session) {
	LexiconONNXRuntimeSession *value = (LexiconONNXRuntimeSession *)session;
	if (value == NULL) {
		return;
	}
	if (value->session != NULL) {
		value->api->ReleaseSession(value->session);
	}
	if (value->env != NULL) {
		value->api->ReleaseEnv(value->env);
	}
	free(value);
}

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
) {
	LexiconONNXRuntimeSession *runtime = (LexiconONNXRuntimeSession *)session;
	if (runtime == NULL || runtime->session == NULL) {
		LexiconONNXRuntimeSetError(error, "ONNX Runtime session has not been created.");
		return 0;
	}
	if (outputValues == NULL || outputValueCount == NULL || outputShape == NULL || outputShapeCount == NULL) {
		LexiconONNXRuntimeSetError(error, "Missing ONNX Runtime output pointer.");
		return 0;
	}
	*outputValues = NULL;
	*outputValueCount = 0;
	*outputShape = NULL;
	*outputShapeCount = 0;

	const OrtApi *api = runtime->api;
	OrtMemoryInfo *memoryInfo = NULL;
	if (!LexiconONNXRuntimeCheck(api, api->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &memoryInfo), error)) {
		return 0;
	}

	size_t inputElementCount = LexiconONNXRuntimeElementCount(shape, shapeCount);
	OrtValue **inputValues = (OrtValue **)calloc(inputCount, sizeof(OrtValue *));
	if (inputValues == NULL) {
		api->ReleaseMemoryInfo(memoryInfo);
		LexiconONNXRuntimeSetError(error, "Could not allocate ONNX Runtime input values.");
		return 0;
	}

	int ok = 1;
	for (size_t index = 0; index < inputCount; ++index) {
		ok = LexiconONNXRuntimeCheck(
			api,
			api->CreateTensorWithDataAsOrtValue(
				memoryInfo,
				(void *)inputData[index],
				inputElementCount * sizeof(int64_t),
				shape,
				shapeCount,
				ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64,
				&inputValues[index]
			),
			error
		);
		if (!ok) {
			break;
		}
	}
	api->ReleaseMemoryInfo(memoryInfo);

	OrtValue *output = NULL;
	const char *outputNames[] = { outputName };
	if (ok) {
		ok = LexiconONNXRuntimeCheck(
			api,
			api->Run(
				runtime->session,
				NULL,
				inputNames,
				(const OrtValue *const *)inputValues,
				inputCount,
				outputNames,
				1,
				&output
			),
			error
		);
	}

	for (size_t index = 0; index < inputCount; ++index) {
		if (inputValues[index] != NULL) {
			api->ReleaseValue(inputValues[index]);
		}
	}
	free(inputValues);

	if (!ok) {
		if (output != NULL) {
			api->ReleaseValue(output);
		}
		return 0;
	}

	OrtTensorTypeAndShapeInfo *info = NULL;
	if (!LexiconONNXRuntimeCheck(api, api->GetTensorTypeAndShape(output, &info), error)) {
		api->ReleaseValue(output);
		return 0;
	}

	ONNXTensorElementDataType elementType;
	ok = LexiconONNXRuntimeCheck(api, api->GetTensorElementType(info, &elementType), error);
	if (ok && elementType != ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT) {
		LexiconONNXRuntimeSetError(error, "ONNX Runtime output tensor is not float.");
		ok = 0;
	}

	size_t dimensionsCount = 0;
	if (ok) {
		ok = LexiconONNXRuntimeCheck(api, api->GetDimensionsCount(info, &dimensionsCount), error);
	}
	int64_t *shapeCopy = NULL;
	if (ok) {
		shapeCopy = (int64_t *)malloc(dimensionsCount * sizeof(int64_t));
		if (shapeCopy == NULL) {
			LexiconONNXRuntimeSetError(error, "Could not allocate ONNX Runtime output shape.");
			ok = 0;
		}
	}
	if (ok) {
		ok = LexiconONNXRuntimeCheck(api, api->GetDimensions(info, shapeCopy, dimensionsCount), error);
	}

	float *data = NULL;
	if (ok) {
		ok = LexiconONNXRuntimeCheck(api, api->GetTensorMutableData(output, (void **)&data), error);
	}
	float *valuesCopy = NULL;
	size_t valueCount = 0;
	if (ok) {
		valueCount = LexiconONNXRuntimeElementCount(shapeCopy, dimensionsCount);
		valuesCopy = (float *)malloc(valueCount * sizeof(float));
		if (valuesCopy == NULL) {
			LexiconONNXRuntimeSetError(error, "Could not allocate ONNX Runtime output values.");
			ok = 0;
		}
	}
	if (ok) {
		memcpy(valuesCopy, data, valueCount * sizeof(float));
		*outputValues = valuesCopy;
		*outputValueCount = valueCount;
		*outputShape = shapeCopy;
		*outputShapeCount = dimensionsCount;
	}

	if (!ok) {
		free(valuesCopy);
		free(shapeCopy);
	}
	api->ReleaseTensorTypeAndShapeInfo(info);
	api->ReleaseValue(output);
	return ok;
}

#else

const char *LexiconONNXRuntimeVersion(void) {
	return "unavailable";
}

int LexiconONNXRuntimeCreateSession(
	const char *modelPath,
	LexiconONNXRuntimeSessionRef *session,
	char **error
) {
	(void)modelPath;
	(void)session;
	LexiconONNXRuntimeSetError(error, "ONNX Runtime C API is not available.");
	return 0;
}

void LexiconONNXRuntimeReleaseSession(LexiconONNXRuntimeSessionRef session) {
	(void)session;
}

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
) {
	(void)session;
	(void)inputNames;
	(void)inputData;
	(void)inputCount;
	(void)shape;
	(void)shapeCount;
	(void)outputName;
	(void)outputValues;
	(void)outputValueCount;
	(void)outputShape;
	(void)outputShapeCount;
	LexiconONNXRuntimeSetError(error, "ONNX Runtime C API is not available.");
	return 0;
}

#endif

void LexiconONNXRuntimeReleaseTensor(float *outputValues, int64_t *outputShape) {
	free(outputValues);
	free(outputShape);
}

void LexiconONNXRuntimeReleaseError(char *error) {
	free(error);
}
