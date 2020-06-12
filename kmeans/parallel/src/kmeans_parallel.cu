#include "kmeans_parallel.cuh"
#include "announce.hh"

void KMeans::main(DataPoint* const centroids, DataPoint* const data) {
    Announce announce(KSize, DataSize, FeatSize);

    cudaAssert (
        cudaHostRegister(data, DataSize*FeatSize*sizeof(Data_T), cudaHostRegisterMapped)
    );
    cudaAssert (
        cudaHostRegister(centroids, KSize*FeatSize*sizeof(Data_T), cudaHostRegisterMapped)
    );

    //study(deviceQuery());

    int numThread_labeling = 64; /*TODO get from study*/
    int numBlock_labeling = ceil((float)DataSize / numThread_labeling);

    auto newCentroids = new DataPoint[KSize];
    int threashold = 47; // 
    while(true && threashold-- > 0) {
        KMeans::labeling<<<numBlock_labeling, numThread_labeling>>>(centroids, data);
        cudaDeviceSynchronize();
        //cudaAssert(cudaPeekAtLastError());

        announce.Labels(data);

        resetNewCentroids(newCentroids);
        KMeans::updateCentroid(newCentroids, data);

        if(KMeans::isSame(centroids, newCentroids))
            break;

        cudaMemcpy (
            (void*)centroids,
            (void*)newCentroids,
            KSize*sizeof(DataPoint),
            cudaMemcpyHostToDevice
        );
    }


    delete[] newCentroids;
    cudaFreeHost(data);
    cudaFreeHost(centroids);
}


void resetNewCentroids(DataPoint* newCentroids) {
    for(int i=0; i!=KSize; ++i) {
        newCentroids[i].label = i;
        Data_T* valuePtr = newCentroids[i].value;
        
        for(int j=0; j!=FeatSize; ++j) {
            *valuePtr = 0.0;
            valuePtr++;
        }
    }

    for(int i=0; i!=KSize; ++i) {
        for(int j=0; j!=FeatSize; ++j) {
            assert(newCentroids[i].value[j] == 0);
        }
    }
}

/// initCentroids /////////////////////////////////////////////////////////////////////////////

void KMeans::initCentroids(DataPoint* const centroids, const DataPoint* const data) {
    for(int kIdx=0; kIdx!=KSize; ++kIdx) {
        centroids[kIdx].label = kIdx;

        for(int featIdx=0; featIdx!=FeatSize; ++featIdx) {
            centroids[kIdx].value[featIdx] = data[kIdx].value[featIdx];
        }
    }
}

/// labeling ////////////////////////////////////////////////////////////////////////////////////
__global__
void KMeans::labeling(const DataPoint* const centroids, DataPoint* const data) {
    const int& idx = blockIdx.x * blockDim.x + threadIdx.x;
    if(idx >= 59900) {
        printf("%d\n",idx);
    }
    if(idx >= DataSize)
        return;
    Labeling::setClosestCentroid(centroids, data+idx);
}

__device__
void KMeans::Labeling::setClosestCentroid( const DataPoint* centroids, DataPoint* const data) {
    const DataPoint* centroidPtr = centroids;
    size_t minDistLabel = 0;
    Data_T minDistSQR = MaxDataValue;

    for(int kIdx=0; kIdx!=KSize; ++kIdx) {
        Data_T currDistSQR = euclideanDistSQR(centroidPtr, data);

        if(minDistSQR > currDistSQR) {
            minDistLabel = centroidPtr->label;
            minDistSQR = currDistSQR;
        }

        centroidPtr++;
    }

    data->label = minDistLabel;
}

__device__
Data_T KMeans::Labeling::euclideanDistSQR ( const DataPoint* const lhs, const DataPoint* const rhs) {
    const Data_T* valuePtrLHS = lhs->value;
    const Data_T* valuePtrRHS = rhs->value;

    Data_T distSQR = 0;

    for(int featIdx=0; featIdx!=FeatSize; ++featIdx) {
        Data_T dist = *valuePtrLHS - *valuePtrRHS;

        distSQR += dist*dist;

        valuePtrLHS++;
        valuePtrRHS++;
    }

    return distSQR;
}

/// update centroids //////////////////////////////////////////////////////////////////////////////

void KMeans::updateCentroid(DataPoint* const centroids, const DataPoint* const data) {
    int labelSizes[KSize] = {0,}; 
    
    // 모든 데이터 포인트의 값을 해당하는 centroid에 더한다.
    const DataPoint* dataPtr = data;
    for(int dataIdx=0; dataIdx!=DataSize; ++dataIdx) {
        Update::addValuesLtoR(dataPtr->value, centroids[dataPtr->label].value);

        labelSizes[dataPtr->label]++;
        dataPtr++;
    }

    DataPoint* centroidPtr = centroids;
    for(int kIdx=0; kIdx!=KSize; ++kIdx) {
        int label = centroidPtr->label;
        Data_T* valuePtr = centroidPtr->value;

        for(int featIdx=0; featIdx!=FeatSize; ++featIdx) {
            *(valuePtr++) /= labelSizes[label];
        }
        centroidPtr++;
    }
}

void KMeans::Update::addValuesLtoR(const Data_T* const lhs, Data_T* const rhs) {
    const Data_T* lhsPtr = lhs;
    Data_T* rhsPtr = rhs;

    for(int featIdx=0; featIdx!=FeatSize; ++featIdx)
        *(rhsPtr++) += *(lhsPtr++);
}

bool KMeans::isSame(DataPoint* const centroids, DataPoint* const newCentroids) {
    DataPoint* prevCentroidPtr = centroids;
    DataPoint* newCentroidPtr = newCentroids;

    for(int kIdx=0; kIdx!=KSize; ++kIdx) {
        Data_T* prevValuePtr = prevCentroidPtr->value;
        Data_T* newValuePtr = newCentroidPtr->value;

        for(int featIdx=0; featIdx!=FeatSize; ++featIdx) {
            if(*prevValuePtr != *newValuePtr)
                return false;

            prevValuePtr++;
            newValuePtr++;
        }

        prevCentroidPtr++;
        newCentroidPtr++;
    }
    return true;
}

void study(const std::vector<DeviceQuery>& devices) {
    /*
     * According to the CUDA C Best Practice Guide.
     * 1. Thread per block should be a multiple of 32(warp size)
     * 2. A minimum of 64 threads per block should be used.
     * 3. Between 128 and 256 thread per block is a better choice
     * 4. Use several(3 to 4) small thread blocks rather than one large thread block
     */
    /* 
     * sizeof DataPoint 
     *   = 4(float) * 200(feature size) + 4(label, int) 
     *   = 804 byte
     *   =>register memory per thread
     *     = 832 byte { 804 + 8(pointer) + 8(two int) + 8(size_t) + 4(Data_T) }
     *   =>register count per thread
     *     = 832/4 = 208
     *
     * sizeof Centroid
     *   = DataPoint x 10
     *   = 8040 byte
     * 
     * memory per block (* NOT SHARED MEMORY *)
     *   = 804 * 64 
     *   = 51456 byte
     *
     * total global memory size = 8112 MBytes
     * number of registers per block = 65536
     */
    Count_T numRegisterPerKernel_labeling = 208;
    MemSize_L sizeDataPoint = sizeof(DataPoint);
    MemSize_L sizeCentroids = sizeDataPoint * KSize;
    for(auto device : devices) {
        assert(sizeCentroids < device.totalConstMem);

        std::cout <<  "Device["<<device.index<<"]" << std::endl;

        Count_T maxThreadsPerBlock = device.numRegPerBlock / numRegisterPerKernel_labeling;
        std::cout <<"max threads per block(labeling) : " << maxThreadsPerBlock << std::endl;
        std::cout <<"max threads per block(update)   : " << maxThreadsPerBlock << std::endl;
        std::cout <<"max threads per block(check)    : " << maxThreadsPerBlock << std::endl;

        std::cout << device.numRegPerBlock / 208.0 << std::endl;
        std::cout << device.threadsPerBlock << std::endl;
        std::cout << device.threadsPerMultiprocesser << std::endl;
    }
}
