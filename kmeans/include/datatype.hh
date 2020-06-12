#ifndef __DATATYPE_HH__
#define __DATATYPE_HH__
#include "npy.hh" // npy size_t
#include <vector>

using Data_T = float;
using Data_V = std::vector<Data_T>;

static const size_t MaxDataValue = 987654321.0;

static const size_t KSize = 10;
static const size_t DataSize = 60000;
static const size_t FeatSize = 200;

struct DataPoint {
    int label = 0;
    Data_T value[FeatSize];
};

inline bool cmpDataPoint(const DataPoint& p1, const DataPoint& p2) {
    return p1.label < p2.label;
}

#endif
