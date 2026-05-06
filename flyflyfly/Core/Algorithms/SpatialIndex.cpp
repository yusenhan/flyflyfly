#include "SpatialIndex.hpp"
#include <algorithm>

QuadtreeNode::QuadtreeNode(CPPBoundingBox box) : boundary(box) {}

void QuadtreeNode::subdivide() {
    double midLat = (boundary.minLat + boundary.maxLat) / 2.0;
    double midLon = (boundary.minLon + boundary.maxLon) / 2.0;

    children[0] = std::make_unique<QuadtreeNode>(CPPBoundingBox{midLat, boundary.maxLat, boundary.minLon, midLon}); // NW
    children[1] = std::make_unique<QuadtreeNode>(CPPBoundingBox{midLat, boundary.maxLat, midLon, boundary.maxLon}); // NE
    children[2] = std::make_unique<QuadtreeNode>(CPPBoundingBox{boundary.minLat, midLat, boundary.minLon, midLon}); // SW
    children[3] = std::make_unique<QuadtreeNode>(CPPBoundingBox{boundary.minLat, midLat, midLon, boundary.maxLon}); // SE
    
    isLeaf = false;
}

void QuadtreeNode::insert(uint32_t index, const std::vector<CPPCoordinate>& allPoints) {
    if (!boundary.contains(allPoints[index])) return;

    if (isLeaf && pointIndices.size() < CAPACITY) {
        pointIndices.push_back(index);
        return;
    }

    if (isLeaf) subdivide();

    for (int i = 0; i < 4; ++i) {
        children[i]->insert(index, allPoints);
    }
}

void QuadtreeNode::query(const CPPBoundingBox& range, const std::vector<CPPCoordinate>& allPoints, std::vector<uint32_t>& foundIndices) const {
    if (!boundary.intersects(range)) return;

    for (uint32_t index : pointIndices) {
        if (range.contains(allPoints[index])) {
            foundIndices.push_back(index);
        }
    }

    if (!isLeaf) {
        for (int i = 0; i < 4; ++i) {
            children[i]->query(range, allPoints, foundIndices);
        }
    }
}

void SpatialIndex::build(const std::vector<CPPCoordinate>& newPoints) {
    points = newPoints;
    if (points.empty()) {
        root = nullptr;
        return;
    }

    double minLat = 90, maxLat = -90, minLon = 180, maxLon = -180;
    for (const auto& p : points) {
        minLat = std::min(minLat, p.latitude);
        maxLat = std::max(maxLat, p.latitude);
        minLon = std::min(minLon, p.longitude);
        maxLon = std::max(maxLon, p.longitude);
    }

    // Add small padding
    root = std::make_unique<QuadtreeNode>(CPPBoundingBox{minLat - 0.01, maxLat + 0.01, minLon - 0.01, maxLon + 0.01});
    for (uint32_t i = 0; i < (uint32_t)points.size(); ++i) {
        root->insert(i, points);
    }
}

std::vector<uint32_t> SpatialIndex::search(CPPBoundingBox range) const {
    std::vector<uint32_t> result;
    if (root) root->query(range, points, result);
    return result;
}
