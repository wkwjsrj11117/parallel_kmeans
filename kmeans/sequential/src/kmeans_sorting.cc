#include "kmeans.hh"
#include "announce.hh"
#include <algorithm>

static int labelSizes[KSize] = {0,}; 
inline void resetLabelSizes() {
    memset(labelSizes, 0, KSize*sizeof(int));
}

void KMeans::main(DataPoint* const centroids, DataPoint* const data) {
    Announce announce(KSize, DataSize, FeatSize);

    auto newCentroids = new DataPoint[KSize];

    while(true) {
        resetLabelSizes();

        KMeans::labeling(centroids, data);
        announce.Labels(data);

        std::sort(data, data+DataSize, cmpDataPoint);

        resetNewCentroids(newCentroids);
        KMeans::updateCentroid(newCentroids, data);

        if(KMeans::isSame(centroids, newCentroids))
            break;

        memcpyCentroid(centroids, newCentroids);
    }

    delete[] newCentroids;
}

/// labeling ////////////////////////////////////////////////////////////////////////////////////

void KMeans::labeling(const DataPoint* const centroids, DataPoint* const data) {
    DataPoint* dataPtr = data;

    for(int dataIdx=0; dataIdx!=DataSize; ++dataIdx)
        Labeling::setClosestCentroid(centroids, dataPtr++);
}

void KMeans::Labeling::setClosestCentroid (const DataPoint* centroids, DataPoint* const data) {
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
    labelSizes[minDistLabel]++;
}

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
    DataPoint* centroidPtr = centroids;
    const DataPoint* dataPtr = data;

    for(int i=0; i!=KSize; ++i) {
        const int labelSize = labelSizes[centroidPtr->label];
        Data_T* valuePtr = centroidPtr->value;

        for(int j=0; j!=labelSize; ++j) {
            Update::addValuesLtoR(dataPtr->value, valuePtr);
            dataPtr++;
        }

        for(int j=0; j!=FeatSize; ++j) {
            *(valuePtr++) /= labelSize;
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

