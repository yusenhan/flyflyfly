#ifndef SpatialIndex_hpp
#define SpatialIndex_hpp

#ifdef __cplusplus
#include <vector>
#include <memory>
#include "FastMotionEngine.hpp"

struct CPPBoundingBox {
    double minLat, maxLat, minLon, maxLon;
    bool contains(CPPCoordinate coord) const {
        return coord.latitude >= minLat && coord.latitude <= maxLat &&
               coord.longitude >= minLon && coord.longitude <= maxLon;
    }
    bool intersects(const CPPBoundingBox& other) const {
        return !(other.minLat > maxLat || other.maxLat < minLat ||
                 other.minLon > maxLon || other.maxLon < minLon);
    }
};

class QuadtreeNode {
    CPPBoundingBox boundary;
    std::vector<uint32_t> pointIndices;
    std::unique_ptr<QuadtreeNode> children[4];
    bool isLeaf = true;
    static constexpr size_t CAPACITY = 64;

public:
    QuadtreeNode(CPPBoundingBox box);
    void insert(uint32_t index, const std::vector<CPPCoordinate>& allPoints);
    void query(const CPPBoundingBox& range, const std::vector<CPPCoordinate>& allPoints, std::vector<uint32_t>& foundIndices) const;
    void subdivide();
};

class SpatialIndex {
    std::vector<CPPCoordinate> points;
    std::unique_ptr<QuadtreeNode> root;
public:
    void build(const std::vector<CPPCoordinate>& newPoints);
    std::vector<uint32_t> search(CPPBoundingBox range) const;
    size_t count() const { return points.size(); }
};
#endif

#endif /* SpatialIndex_hpp */
