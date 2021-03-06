//
//  PhotoBrowserCell.swift
//  PhotoBrowser
//
//  Created by JiongXing on 2017/3/28.
//  Copyright © 2017年 JiongXing. All rights reserved.
//

import UIKit
import Kingfisher

protocol PhotoBrowserCellDelegate: NSObjectProtocol {
    /// 拖动时回调。scale:缩放比率
    func photoBrowserCell(_ cell: PhotoBrowserCell, didPanScale scale: CGFloat)
    
    /// 单击时回调
    func photoBrowserCell(_ cell: PhotoBrowserCell, didSingleTap image: UIImage?)
    
    /// 长按时回调
    func photoBrowserCell(_ cell: PhotoBrowserCell, didLongPressWith image: UIImage)
}

class PhotoBrowserCell: UICollectionViewCell {
    // MARK: - 公开属性
    /// 代理
    weak var photoBrowserCellDelegate: PhotoBrowserCellDelegate?
    
    /// 显示图像
    let imageView = UIImageView()
    
    /// 保存原图url，用于点查看原图时使用
    var rawUrl: URL?
    
    /// 捏合手势放大图片时的最大允许比例
    var imageMaximumZoomScale: CGFloat = 2.0 {
        didSet {
            self.scrollView.maximumZoomScale = imageMaximumZoomScale
        }
    }
    
    /// 双击放大图片时的目标比例
    var imageZoomScaleForDoubleTap: CGFloat = 2.0
    
    // MARK: - 内部属性
    /// 内嵌容器。本类不能继承UIScrollView。
    /// 因为实测UIScrollView遵循了UIGestureRecognizerDelegate协议，而本类也需要遵循此协议，
    /// 若继承UIScrollView则会覆盖UIScrollView的协议实现，故只内嵌而不继承。
    private let scrollView = UIScrollView()
    
    /// 加载进度指示器
    private let progressView = PhotoBrowserProgressView()
    
    /// 查看原图按钮
    private lazy var rawImageButton: UIButton = { [unowned self] in
        let button = UIButton(type: .custom)
        button.setTitleColor(UIColor.white, for: .normal)
        button.setTitleColor(UIColor.white, for: .highlighted)
        button.setTitle("查看原图", for: .normal)
        button.setTitle("查看原图", for: .highlighted)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 12)
        button.layer.borderColor = UIColor.lightGray.cgColor
        button.layer.borderWidth = 1
        button.layer.cornerRadius = 4
        button.layer.masksToBounds = true
        button.addTarget(self, action: #selector(onRawImageButtonTap), for: .touchUpInside)
        return button
        }()
    
    /// 计算contentSize应处于的中心位置
    private var centerOfContentSize: CGPoint {
        let deltaWidth = bounds.width - scrollView.contentSize.width
        let offsetX = deltaWidth > 0 ? deltaWidth * 0.5 : 0
        let deltaHeight = bounds.height - scrollView.contentSize.height
        let offsetY = deltaHeight > 0 ? deltaHeight * 0.5 : 0
        return CGPoint(x: scrollView.contentSize.width * 0.5 + offsetX,
                       y: scrollView.contentSize.height * 0.5 + offsetY)
    }
    
    /// 取图片适屏size
    private var fitSize: CGSize {
        guard let image = imageView.image else {
            return CGSize.zero
        }
        let width = scrollView.bounds.width
        let scale = image.size.height / image.size.width
        return CGSize(width: width, height: scale * width)
    }
    
    /// 取图片适屏frame
    private var fitFrame: CGRect {
        let size = fitSize
        let y = (scrollView.bounds.height - size.height) > 0 ? (scrollView.bounds.height - size.height) * 0.5 : 0
        return CGRect(x: 0, y: y, width: size.width, height: size.height)
    }
    
    /// 记录pan手势开始时imageView的位置
    private var beganFrame = CGRect.zero
    
    /// 记录pan手势开始时，手势位置
    private var beganTouch = CGPoint.zero

    private var shouldLayout = true
    
    // MARK: - 方法
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(scrollView)
        scrollView.delegate = self
        scrollView.maximumZoomScale = imageMaximumZoomScale
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        if #available(iOS 11.0, *) {
            scrollView.contentInsetAdjustmentBehavior = .never
        }

        scrollView.addSubview(imageView)
        imageView.clipsToBounds = true
        
        contentView.addSubview(progressView)
        progressView.isHidden = true
        
        // 长按手势
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(onLongPress(_:)))
        contentView.addGestureRecognizer(longPress)
        
        // 双击手势
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(onDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        contentView.addGestureRecognizer(doubleTap)
        
        // 单击手势
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(onSingleTap))
        contentView.addGestureRecognizer(singleTap)
        singleTap.require(toFail: doubleTap)
        
        // 拖动手势
        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        pan.delegate = self
        scrollView.addGestureRecognizer(pan)
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        layout()
    }
    
    /// 布局
    private func layout() {
        guard shouldLayout else { return }

        scrollView.frame = contentView.bounds
        scrollView.setZoomScale(1.0, animated: false)
        imageView.frame = fitFrame
        scrollView.setZoomScale(1.0, animated: false)
        progressView.center = CGPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
        
        // 查看原图按钮
        if rawImageButton.isHidden == false {
            contentView.addSubview(rawImageButton)
            rawImageButton.sizeToFit()
            rawImageButton.bounds.size.width += 14
            rawImageButton.center = CGPoint(x: contentView.bounds.midX, y: contentView.bounds.height - 20 - rawImageButton.bounds.height)
            rawImageButton.isHidden = false
        }
    }
    
    /// 设置图片。image为placeholder图片，url为网络图片
    func setImage(_ image: UIImage?, highQualityUrl: URL?, rawUrl: URL?) {
        // 默认隐藏查看原图按钮
        self.rawUrl = nil
        rawImageButton.isHidden = true
        // 若已有原图缓存，使用原图
        if let image = imageFor(url: rawUrl) {
            imageView.image = image
            layout()
            return
        }
        // 若已有高清图缓存，使用高清图
        if let image = imageFor(url: highQualityUrl) {
            imageView.image = image
            // 有rawUrl则显示查看原图按钮
            if rawUrl != nil {
                self.rawUrl = rawUrl
                rawImageButton.isHidden = false
            }
            layout()
            return
        }
        // 无缓存，开始加载图片
        if highQualityUrl != nil {
            loadImage(withPlaceholder: image, url: highQualityUrl, completion: { [weak self] in
                if rawUrl != nil {
                    self?.rawUrl = rawUrl
                    self?.rawImageButton.isHidden = false
                }
                self?.layout()
            })
        } else {
            loadImage(withPlaceholder: image, url: rawUrl, completion: { [weak self] in
                self?.layout()
            })
        }
        self.layout()
    }
    
    /// 加载图片
    private func loadImage(withPlaceholder placeholder: UIImage?, url: URL?, completion: (() -> Void)?) {
        // 显示加载进度
        self.progressView.isHidden = false
        imageView.kf.setImage(with: url, placeholder: placeholder, options: nil, progressBlock: { [weak self] (receivedSize, totalSize) in
            if totalSize > 0 {
                self?.progressView.progress = CGFloat(receivedSize) / CGFloat(totalSize)
            }
        }, completionHandler: { [weak self] (image, error, cacheType, url) in
            self?.progressView.isHidden = true
            if let completion = completion {
                completion()
            }
        })
    }
    
    /// 根据url从缓存取图像
    private func imageFor(url: URL?) -> UIImage? {
        guard let url = url else {
            return nil
        }
        var cacheImage: UIImage?
        let result = KingfisherManager.shared.cache.imageCachedType(forKey: url.cacheKey)
        switch result {
        case .none:
            cacheImage = nil
        case .memory:
            cacheImage = KingfisherManager.shared.cache.retrieveImageInMemoryCache(forKey: url.cacheKey)
        case .disk:
            cacheImage = KingfisherManager.shared.cache.retrieveImageInDiskCache(forKey: url.cacheKey)
        }
        return cacheImage
    }
    
    /// 响应单击
    @objc func onSingleTap() {
        if let dlg = photoBrowserCellDelegate {
            dlg.photoBrowserCell(self, didSingleTap: imageView.image)
        }
    }
    
    /// 响应双击
    @objc func onDoubleTap(_ dbTap: UITapGestureRecognizer) {
        // 如果当前没有任何缩放，则放大到目标比例
        // 否则重置到原比例
        if scrollView.zoomScale == 1.0 {
            // 以点击的位置为中心，放大
            let pointInView = dbTap.location(in: imageView)
            let w = scrollView.bounds.size.width / imageZoomScaleForDoubleTap
            let h = scrollView.bounds.size.height / imageZoomScaleForDoubleTap
            let x = pointInView.x - (w / 2.0)
            let y = pointInView.y - (h / 2.0)
            scrollView.zoom(to: CGRect(x: x, y: y, width: w, height: h), animated: true)
        } else {
            scrollView.setZoomScale(1.0, animated: true)
        }
    }
    
    /// 响应拖动
    @objc func onPan(_ pan: UIPanGestureRecognizer) {
        guard imageView.image != nil else {
            return
        }

        var results: (CGRect, CGFloat) {
            // 拖动偏移量
            let translation = pan.translation(in: scrollView)
            let currentTouch = pan.location(in: scrollView)

            // 由下拉的偏移值决定缩放比例，越往下偏移，缩得越小。scale值区间[0.3, 1.0]
            let scale = min(1.0, max(0.3, 1 - translation.y / bounds.height))

            let width = beganFrame.size.width * scale
            let height = beganFrame.size.height * scale

            // 计算x和y。保持手指在图片上的相对位置不变。
            // 即如果手势开始时，手指在图片X轴三分之一处，那么在移动图片时，保持手指始终位于图片X轴的三分之一处
            let xRate = (beganTouch.x - beganFrame.origin.x) / beganFrame.size.width
            let currentTouchDeltaX = xRate * width
            let x = currentTouch.x - currentTouchDeltaX

            let yRate = (beganTouch.y - beganFrame.origin.y) / beganFrame.size.height
            let currentTouchDeltaY = yRate * height
            let y = currentTouch.y - currentTouchDeltaY

            return (CGRect(x: x, y: y, width: width, height: height), scale)
        }

        switch pan.state {
        case .began:
            beganFrame = imageView.frame
            beganTouch = pan.location(in: scrollView)
        case .changed:
            let r = results
            imageView.frame = r.0

            // 通知代理，发生了缩放。代理可依scale值改变背景蒙板alpha值
            if let dlg = photoBrowserCellDelegate {
                dlg.photoBrowserCell(self, didPanScale: r.1)
            }
        case .ended, .cancelled:
            if pan.velocity(in: self).y > 0 {
                // dismiss
                shouldLayout = false
                imageView.frame = results.0
                onSingleTap()
            } else {
                // 取消dismiss
                endPan()
            }
        default:
            endPan()
        }
    }
    
    private func endPan() {
        if let dlg = photoBrowserCellDelegate {
            dlg.photoBrowserCell(self, didPanScale: 1.0)
        }
        // 如果图片当前显示的size小于原size，则重置为原size
        let size = fitSize
        let needResetSize = imageView.bounds.size.width < size.width
            || imageView.bounds.size.height < size.height
        UIView.animate(withDuration: 0.25) {
            self.imageView.center = self.centerOfContentSize
            if needResetSize {
                self.imageView.bounds.size = size
            }
        }
    }
    
    /// 响应长按
    @objc func onLongPress(_ press: UILongPressGestureRecognizer) {
        if press.state == .began, let dlg = photoBrowserCellDelegate, let image = imageView.image {
            dlg.photoBrowserCell(self, didLongPressWith: image)
        }
    }
    
    /// 响应查看原图按钮
    @objc func onRawImageButtonTap() {
        rawImageButton.isHidden = true
        loadImage(withPlaceholder: imageView.image, url: rawUrl, completion: { [weak self] in
            self?.layout()
        })
    }
}

extension PhotoBrowserCell: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
    
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        imageView.center = centerOfContentSize
    }
}

extension PhotoBrowserCell: UIGestureRecognizerDelegate {
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // 只响应pan手势
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else {
            return true
        }
        let velocity = pan.velocity(in: self)
        // 向上滑动时，不响应手势
        if velocity.y < 0 {
            return false
        }
        // 横向滑动时，不响应pan手势
        if abs(Int(velocity.x)) > Int(velocity.y) {
            return false
        }
        // 向下滑动，如果图片顶部超出可视区域，不响应手势
        if scrollView.contentOffset.y > 0 {
            return false
        }
        return true
    }
}
