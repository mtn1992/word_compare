import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:rect_getter/rect_getter.dart';

void main() => runApp(const DocumentCheckerApp());

class DocumentCheckerApp extends StatelessWidget {
  const DocumentCheckerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '文档查重工具',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const DocumentCheckerHomePage(),
    );
  }
}

class DocumentCheckerHomePage extends StatefulWidget {
  const DocumentCheckerHomePage({super.key});

  @override
  State<DocumentCheckerHomePage> createState() =>
      _DocumentCheckerHomePageState();
}

class _DocumentCheckerHomePageState extends State<DocumentCheckerHomePage> {
  String? _filePath1;
  String? _filePath2;
  String _content1 = '';
  String _content2 = '';

  int _threshold = 5;
  double _similarityRate = 0.0;

  // 滚动控制器
  final ScrollController _scrollController1 = ScrollController();
  final ScrollController _scrollController2 = ScrollController();

  List<TextElement> _elements1 = [];
  List<TextElement> _elements2 = [];

  // 存储重复句子的对应关系
  final Map<int, List<int>> _duplicatePairs = {};
  final Map<int, List<int>> _reverseDuplicatePairs = {};

  // 存储句子级别的重复率信息
  final Map<int, double> _sentenceSimilarity1 = {};
  final Map<int, double> _sentenceSimilarity2 = {};

  // 高亮的句子索引
  final Set<int> _highlightedSentences1 = {};
  final Set<int> _highlightedSentences2 = {};

  // RectGetter Keys - 修复类型声明
  final GlobalKey<RectGetterState> _listViewKey1 = RectGetter.createGlobalKey();
  final GlobalKey<RectGetterState> _listViewKey2 = RectGetter.createGlobalKey();
  final Map<int, GlobalKey<RectGetterState>> _itemKeys1 = {};
  final Map<int, GlobalKey<RectGetterState>> _itemKeys2 = {};

  // 添加下一个重复句子的索引跟踪
  int _nextDuplicateIndex1 = 0;
  int _nextDuplicateIndex2 = 0;
  List<int> _duplicateSentences1 = [];
  List<int> _duplicateSentences2 = [];

  final TextEditingController _thresholdController = TextEditingController();

  // 加载状态和进度
  bool _isLoading = false;
  double _loadingProgress = 0.0;
  String _loadingMessage = '';

  // 添加比较状态
  bool _isComparing = false;

  @override
  void initState() {
    super.initState();
    _thresholdController.text = _threshold.toString();
  }

  @override
  void dispose() {
    _thresholdController.dispose();
    _scrollController1.dispose();
    _scrollController2.dispose();
    super.dispose();
  }

  // 加载文档
  Future<void> _loadDocument(int documentIndex) async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _loadingProgress = 0.0;
      _loadingMessage = documentIndex == 1 ? '正在加载文档1...' : '正在加载文档2...';
    });

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['docx', 'txt'],
      );

      if (result != null && result.files.single.path != null) {
        String filePath = result.files.single.path!;
        if (!mounted) return;
        setState(() => _loadingProgress = 0.2);

        String content = '';
        if (filePath.toLowerCase().endsWith('.txt')) {
          content = await _readTextFile(filePath);
        } else {
          content = await _extractTextFromDocx(filePath);
        }

        if (!mounted) return;
        setState(() => _loadingProgress = 0.8);

        setState(() {
          if (documentIndex == 1) {
            _filePath1 = filePath;
            _content1 = content;
            _elements1 = [];
            _itemKeys1.clear();
            _duplicateSentences1 = [];
            _sentenceSimilarity1.clear();
            _nextDuplicateIndex1 = 0;
          } else {
            _filePath2 = filePath;
            _content2 = content;
            _elements2 = [];
            _itemKeys2.clear();
            _duplicateSentences2 = [];
            _sentenceSimilarity2.clear();
            _nextDuplicateIndex2 = 0;
          }
          _loadingProgress = 0.9;
        });

        if (_filePath1 != null && _filePath2 != null) {
          await _compareDocuments();
        }

        if (!mounted) return;
        setState(() => _loadingProgress = 1.0);
      }
    } catch (e) {
      debugPrint('加载文档错误: $e');
      if (mounted) {
        _showSnackBar('加载失败: ${e.toString()}');
      }
    } finally {
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // 显示SnackBar的辅助方法
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // 显示句子重复率提示
  // void _showSentenceSimilarity(
  //     int index, bool isFirstDocument, double similarity) {
  //   final sentence =
  //       isFirstDocument ? _elements1[index].text : _elements2[index].text;
  //   final shortSentence =
  //       sentence.length > 50 ? '${sentence.substring(0, 50)}...' : sentence;

  //   ScaffoldMessenger.of(context).showSnackBar(
  //     SnackBar(
  //       content: Column(
  //         crossAxisAlignment: CrossAxisAlignment.start,
  //         mainAxisSize: MainAxisSize.min,
  //         children: [
  //           Text(
  //             '句子重复率: ${similarity.toStringAsFixed(2)}%',
  //             style: const TextStyle(fontWeight: FontWeight.bold),
  //           ),
  //           const SizedBox(height: 4),
  //           Text(
  //             '内容: $shortSentence',
  //             style: const TextStyle(fontSize: 12),
  //             maxLines: 2,
  //             overflow: TextOverflow.ellipsis,
  //           ),
  //         ],
  //       ),
  //       duration: const Duration(seconds: 3),
  //       behavior: SnackBarBehavior.floating,
  //     ),
  //   );
  // }

  // 读取文本文件
  Future<String> _readTextFile(String filePath) async {
    try {
      final file = File(filePath);
      return await file.readAsString();
    } catch (e) {
      return '读取文本文件失败: ${e.toString()}';
    }
  }

  // 解析docx文件
  Future<String> _extractTextFromDocx(String filePath) async {
    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      if (mounted) {
        setState(() => _loadingProgress = 0.5);
      }

      final archive = ZipDecoder().decodeBytes(bytes);
      if (mounted) {
        setState(() => _loadingProgress = 0.7);
      }

      for (final file in archive) {
        if (file.name == 'word/document.xml') {
          final xmlContent = utf8.decode(file.content);
          return _parseXmlContent(xmlContent);
        }
      }
      return '未找到文档内容';
    } catch (e) {
      debugPrint('解析文档错误：$e');
      return '文档解析失败：${e.toString()}';
    }
  }

  // 简化XML内容解析
  String _parseXmlContent(String xmlContent) {
    String text = xmlContent
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'&[^;]+;'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    //if (text.length > 100000) {
    //text = text.substring(0, 100000) + '...（内容已截断）';
    //}

    return text;
  }

  // 重新比对
  Future<void> _onRecheckPressed() async {
    final newThreshold = int.tryParse(_thresholdController.text);
    if (newThreshold != null && newThreshold > 0) {
      setState(() {
        _threshold = newThreshold;
        _clearHighlights();
        _nextDuplicateIndex1 = 0;
        _nextDuplicateIndex2 = 0;
      });
      await _compareDocuments();
    } else {
      _showSnackBar('请输入有效的阈值数值（大于0）');
    }
  }

  // 文档比较逻辑
  Future<void> _compareDocuments() async {
    if (_isComparing) return;

    setState(() {
      _isComparing = true;
      _isLoading = true;
      _loadingMessage = '正在比较文档...';
      _loadingProgress = 0.0;
    });

    try {
      await Future.delayed(const Duration(milliseconds: 100));

      List<String> sentences1 = _splitIntoSentences(_content1);
      List<String> sentences2 = _splitIntoSentences(_content2);

      if (!mounted) return;
      setState(() => _loadingProgress = 0.3);

      // 初始化句子键
      _itemKeys1.clear();
      _itemKeys2.clear();
      for (int i = 0; i < sentences1.length; i++) {
        _itemKeys1[i] = RectGetter.createGlobalKey();
      }
      for (int i = 0; i < sentences2.length; i++) {
        _itemKeys2[i] = RectGetter.createGlobalKey();
      }

      _elements1 = sentences1
          .map((s) => TextElement(text: s, isDuplicate: false))
          .toList();
      _elements2 = sentences2
          .map((s) => TextElement(text: s, isDuplicate: false))
          .toList();

      _duplicatePairs.clear();
      _reverseDuplicatePairs.clear();
      _sentenceSimilarity1.clear();
      _sentenceSimilarity2.clear();
      _clearHighlights();

      // 重置重复句子列表
      _duplicateSentences1.clear();
      _duplicateSentences2.clear();
      _nextDuplicateIndex1 = 0;
      _nextDuplicateIndex2 = 0;

      if (!mounted) return;
      setState(() => _loadingProgress = 0.5);

      await _batchCompareSentences(sentences1, sentences2);

      // 收集重复句子的索引
      for (int i = 0; i < _elements1.length; i++) {
        if (_elements1[i].isDuplicate) {
          _duplicateSentences1.add(i);
        }
      }
      for (int i = 0; i < _elements2.length; i++) {
        if (_elements2[i].isDuplicate) {
          _duplicateSentences2.add(i);
        }
      }

      if (!mounted) return;
      setState(() => _loadingProgress = 0.8);

      _calculateSimilarity(sentences1, sentences2);

      if (!mounted) return;
      setState(() => _loadingProgress = 1.0);

      if (mounted) {
        _showSnackBar('文档比较完成，重复率: ${_similarityRate.toStringAsFixed(2)}%');
      }
    } catch (e) {
      debugPrint('比较文档错误: $e');
      if (mounted) {
        _showSnackBar('比较失败: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isComparing = false;
          _isLoading = false;
        });
      }
    }
  }

  // 分批比较句子
  Future<void> _batchCompareSentences(
      List<String> sentences1, List<String> sentences2) async {
    const int batchSize = 10;

    for (int i = 0; i < sentences1.length; i += batchSize) {
      if (!mounted) break;

      int end = i + batchSize;
      if (end > sentences1.length) end = sentences1.length;

      for (int j = i; j < end; j++) {
        String sentence1 = sentences1[j];
        for (int k = 0; k < sentences2.length; k++) {
          String sentence2 = sentences2[k];
          int maxContinuousMatch =
              _countMaxContinuousCommonCharacters(sentence1, sentence2);

          if (maxContinuousMatch >= _threshold) {
            _elements1[j] = TextElement(text: sentence1, isDuplicate: true);
            _elements2[k] = TextElement(text: sentence2, isDuplicate: true);

            // 计算句子级别的重复率
            double similarity1 =
                _calculateSentenceSimilarity(sentence1, sentence2);
            double similarity2 =
                _calculateSentenceSimilarity(sentence2, sentence1);

            // 记录最大重复率
            if (!_sentenceSimilarity1.containsKey(j) ||
                _sentenceSimilarity1[j]! < similarity1) {
              _sentenceSimilarity1[j] = similarity1;
            }
            if (!_sentenceSimilarity2.containsKey(k) ||
                _sentenceSimilarity2[k]! < similarity2) {
              _sentenceSimilarity2[k] = similarity2;
            }

            if (!_duplicatePairs.containsKey(j)) {
              _duplicatePairs[j] = [];
            }
            _duplicatePairs[j]!.add(k);

            if (!_reverseDuplicatePairs.containsKey(k)) {
              _reverseDuplicatePairs[k] = [];
            }
            _reverseDuplicatePairs[k]!.add(j);
          }
        }
      }

      if (mounted) {
        setState(() {
          _loadingProgress = 0.5 + 0.3 * (end / sentences1.length);
        });
      }

      await Future.delayed(const Duration(milliseconds: 10));
    }
  }

  // 计算句子级别的重复率
  double _calculateSentenceSimilarity(String s1, String s2) {
    if (s1.isEmpty || s2.isEmpty) return 0.0;

    int maxContinuousMatch = _countMaxContinuousCommonCharacters(s1, s2);
    int minLength = s1.length < s2.length ? s1.length : s2.length;

    // 计算重复率：最长连续匹配长度 / 较短句子的长度
    return (maxContinuousMatch / minLength) * 100;
  }

  // 分割句子
  List<String> _splitIntoSentences(String text) {
    if (text.isEmpty) return [];

    return text
        .split(RegExp(r'[;；。！？!?]'))
        .where((s) => s.trim().length > 2)
        .map((s) => s.trim())
        //.take(1000)
        .toList();
  }

  // 计算最长连续相同字符
  int _countMaxContinuousCommonCharacters(String s1, String s2) {
    if (s1.isEmpty || s2.isEmpty) return 0;

    int maxLength = 0;
    int currentLength = 0;

    int minLength = s1.length < s2.length ? s1.length : s2.length;
    for (int i = 0; i < minLength; i++) {
      if (s1[i] == s2[i]) {
        currentLength++;
        if (currentLength > maxLength) {
          maxLength = currentLength;
        }
      } else {
        currentLength = 0;
      }
    }

    return maxLength;
  }

  // 计算重复率
  void _calculateSimilarity(List<String> sentences1, List<String> sentences2) {
    int totalDuplicates = _elements1.where((e) => e.isDuplicate).length;
    int totalSentences = sentences1.length + sentences2.length;
    _similarityRate =
        totalSentences > 0 ? (totalDuplicates / totalSentences) * 100 : 0.0;
  }

  // 点击重复内容
  void _onDuplicateTap(int index, bool isFirstDocument) {
    setState(() {
      _clearHighlights();

      if (isFirstDocument) {
        List<int>? targetIndices = _duplicatePairs[index];
        if (targetIndices != null) {
          for (int targetIndex in targetIndices) {
            _highlightedSentences2.add(targetIndex);
          }

          if (targetIndices.isNotEmpty) {
            _scrollToSentence(targetIndices.first, false);
          }
        }

        // // 显示句子重复率提示
        // if (_sentenceSimilarity1.containsKey(index)) {
        //   _showSentenceSimilarity(index, true, _sentenceSimilarity1[index]!);
        // }

        // 更新下一个重复句子的索引
        if (_duplicateSentences1.isNotEmpty) {
          int currentIndex = _duplicateSentences1.indexOf(index);
          if (currentIndex != -1) {
            _nextDuplicateIndex1 =
                (currentIndex + 1) % _duplicateSentences1.length;
          }
        }
      } else {
        List<int>? targetIndices = _reverseDuplicatePairs[index];
        if (targetIndices != null) {
          for (int targetIndex in targetIndices) {
            _highlightedSentences1.add(targetIndex);
          }

          if (targetIndices.isNotEmpty) {
            _scrollToSentence(targetIndices.first, true);
          }
        }

        // // 显示句子重复率提示
        // if (_sentenceSimilarity2.containsKey(index)) {
        //   _showSentenceSimilarity(index, false, _sentenceSimilarity2[index]!);
        // }

        // 更新下一个重复句子的索引
        if (_duplicateSentences2.isNotEmpty) {
          int currentIndex = _duplicateSentences2.indexOf(index);
          if (currentIndex != -1) {
            _nextDuplicateIndex2 =
                (currentIndex + 1) % _duplicateSentences2.length;
          }
        }
      }
    });
  }

  // 跳转到下一个重复句子 - 文档1
  void _nextDuplicate1() {
    if (_duplicateSentences1.isEmpty) {
      _showSnackBar('文档1中没有重复句子');
      return;
    }

    setState(() {
      _clearHighlights();

      int targetIndex = _duplicateSentences1[_nextDuplicateIndex1];
      _highlightedSentences1.add(targetIndex);

      // // 显示句子重复率提示
      // if (_sentenceSimilarity1.containsKey(targetIndex)) {
      //   _showSentenceSimilarity(
      //       targetIndex, true, _sentenceSimilarity1[targetIndex]!);
      // }

      // 高亮对应的文档2中的句子
      List<int>? targetIndices = _duplicatePairs[targetIndex];
      if (targetIndices != null) {
        for (int targetIndex in targetIndices) {
          _highlightedSentences2.add(targetIndex);
        }

        if (targetIndices.isNotEmpty) {
          _scrollToSentence(targetIndices.first, false);
        }
      }

      _scrollToSentence(targetIndex, true);

      // 更新下一个索引
      _nextDuplicateIndex1 =
          (_nextDuplicateIndex1 + 1) % _duplicateSentences1.length;
    });
  }

  // 跳转到下一个重复句子 - 文档2
  void _nextDuplicate2() {
    if (_duplicateSentences2.isEmpty) {
      _showSnackBar('文档2中没有重复句子');
      return;
    }

    setState(() {
      _clearHighlights();

      int targetIndex = _duplicateSentences2[_nextDuplicateIndex2];
      _highlightedSentences2.add(targetIndex);

      // // 显示句子重复率提示
      // if (_sentenceSimilarity2.containsKey(targetIndex)) {
      //   _showSentenceSimilarity(
      //       targetIndex, false, _sentenceSimilarity2[targetIndex]!);
      // }

      // 高亮对应的文档1中的句子
      List<int>? targetIndices = _reverseDuplicatePairs[targetIndex];
      if (targetIndices != null) {
        for (int targetIndex in targetIndices) {
          _highlightedSentences1.add(targetIndex);
        }

        if (targetIndices.isNotEmpty) {
          _scrollToSentence(targetIndices.first, true);
        }
      }

      _scrollToSentence(targetIndex, false);

      // 更新下一个索引
      _nextDuplicateIndex2 =
          (_nextDuplicateIndex2 + 1) % _duplicateSentences2.length;
    });
  }

  // 使用RectGetter实现精准滚动定位
  void _scrollToSentence(int targetIndex, bool isFirstDocument) {
    final listViewKey = isFirstDocument ? _listViewKey1 : _listViewKey2;
    final itemKeys = isFirstDocument ? _itemKeys1 : _itemKeys2;
    final scrollController =
        isFirstDocument ? _scrollController1 : _scrollController2;

    // 等待一小段时间确保列表已经构建完成
    Future.delayed(const Duration(milliseconds: 50), () {
      if (!mounted) return;

      _performPreciseScroll(
          targetIndex, listViewKey, itemKeys, scrollController);
    });
  }

  // 执行精准滚动
  void _performPreciseScroll(
      int targetIndex,
      GlobalKey<RectGetterState> listViewKey,
      Map<int, GlobalKey<RectGetterState>> itemKeys,
      ScrollController scrollController) {
    // 获取ListView的Rect
    final listViewRect = RectGetter.getRectFromKey(listViewKey);
    if (listViewRect == null) {
      _fallbackScroll(targetIndex, scrollController);
      return;
    }

    // 获取当前可见的条目
    final visibleItems = _getVisibleItems(listViewRect, itemKeys);

    // 检查目标是否在可见范围内
    if (visibleItems.contains(targetIndex)) {
      // 目标已在可见范围内，直接精确对齐
      _alignItemToTop(targetIndex, listViewRect, itemKeys, scrollController);
    } else {
      // 目标不在可见范围内，先滚动到大致区域
      _scrollToRegion(
          targetIndex, listViewRect, itemKeys, scrollController, visibleItems);
    }
  }

  // 获取当前可见的条目索引
  List<int> _getVisibleItems(
      Rect listViewRect, Map<int, GlobalKey<RectGetterState>> itemKeys) {
    List<int> visibleItems = [];

    itemKeys.forEach((index, key) {
      final itemRect = RectGetter.getRectFromKey(key);
      if (itemRect != null && _isItemVisible(itemRect, listViewRect)) {
        visibleItems.add(index);
      }
    });

    visibleItems.sort();
    return visibleItems;
  }

  // 判断条目是否在可视区域内
  bool _isItemVisible(Rect itemRect, Rect listViewRect) {
    return itemRect.bottom > listViewRect.top &&
        itemRect.top < listViewRect.bottom;
  }

  // 将条目精确对齐到顶部
  void _alignItemToTop(
      int targetIndex,
      Rect listViewRect,
      Map<int, GlobalKey<RectGetterState>> itemKeys,
      ScrollController scrollController) {
    final targetKey = itemKeys[targetIndex];
    if (targetKey == null) {
      _fallbackScroll(targetIndex, scrollController);
      return;
    }

    final targetRect = RectGetter.getRectFromKey(targetKey);
    if (targetRect == null) {
      _fallbackScroll(targetIndex, scrollController);
      return;
    }

    // 计算需要滚动的距离
    final double offsetDifference = targetRect.top - listViewRect.top;
    scrollController.jumpTo(scrollController.offset + offsetDifference);
  }

  // 滚动到目标区域
  void _scrollToRegion(
      int targetIndex,
      Rect listViewRect,
      Map<int, GlobalKey<RectGetterState>> itemKeys,
      ScrollController scrollController,
      List<int> visibleItems) {
    // 确定滚动方向
    final bool scrollDown =
        visibleItems.isEmpty || targetIndex > visibleItems.last;
    final double scrollStep = listViewRect.height * (scrollDown ? 1 : -1);

    // 计算新的滚动位置
    double newOffset = scrollController.offset + scrollStep;
    newOffset = newOffset.clamp(0.0, scrollController.position.maxScrollExtent);

    // 执行滚动
    scrollController.jumpTo(newOffset);

    // 递归检查直到目标可见
    Future.delayed(const Duration(milliseconds: 30), () {
      if (!mounted) return;

      final updatedListViewRect = RectGetter.getRectFromKey(_listViewKey1);
      if (updatedListViewRect == null) return;

      final updatedVisibleItems =
          _getVisibleItems(updatedListViewRect, itemKeys);

      if (updatedVisibleItems.contains(targetIndex)) {
        // 目标已可见，进行精确对齐
        _alignItemToTop(
            targetIndex, updatedListViewRect, itemKeys, scrollController);
      } else {
        // 继续滚动
        _scrollToRegion(targetIndex, updatedListViewRect, itemKeys,
            scrollController, updatedVisibleItems);
      }
    });
  }

  // 备用滚动方案
  void _fallbackScroll(int index, ScrollController scrollController) {
    const double estimatedItemHeight = 80.0;
    final double viewportHeight = scrollController.position.viewportDimension;
    final double targetOffset =
        (index * estimatedItemHeight) - (viewportHeight / 3);

    scrollController.animateTo(
      targetOffset.clamp(0.0, scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  // 清除高亮
  void _clearHighlights() {
    _highlightedSentences1.clear();
    _highlightedSentences2.clear();
  }

  // 获取文件名
  String _getFileName(String? filePath) {
    if (filePath == null) return "未选择文件";
    return p.basename(filePath);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Word文档查重工具v1.0')),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton(
                          onPressed: _isLoading ? null : () => _loadDocument(1),
                          child: Text(_filePath1 == null ? '选择文档1' : '更换文档1'),
                        ),
                        ElevatedButton(
                          onPressed: _isLoading ? null : () => _loadDocument(2),
                          child: Text(_filePath2 == null ? '选择文档2' : '更换文档2'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('连续重复字数: '),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 80,
                          child: TextField(
                            controller: _thresholdController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              hintText: '阈值',
                              isDense: true,
                              contentPadding: EdgeInsets.all(8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton(
                          onPressed: (_isLoading ||
                                  _filePath1 == null ||
                                  _filePath2 == null)
                              ? null
                              : _onRecheckPressed,
                          child: const Text('重新比对'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '整体重复率: ${_similarityRate.toStringAsFixed(2)}%',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _buildDocumentView(
                        title: '文档1: ${_getFileName(_filePath1)}',
                        elements: _elements1,
                        highlightedSentences: _highlightedSentences1,
                        itemKeys: _itemKeys1,
                        listViewKey: _listViewKey1,
                        scrollController: _scrollController1,
                        onTap: (index) => _onDuplicateTap(index, true),
                        onNextDuplicate: _nextDuplicate1,
                        hasDuplicates: _duplicateSentences1.isNotEmpty,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: _buildDocumentView(
                        title: '文档2: ${_getFileName(_filePath2)}',
                        elements: _elements2,
                        highlightedSentences: _highlightedSentences2,
                        itemKeys: _itemKeys2,
                        listViewKey: _listViewKey2,
                        scrollController: _scrollController2,
                        onTap: (index) => _onDuplicateTap(index, false),
                        onNextDuplicate: _nextDuplicate2,
                        hasDuplicates: _duplicateSentences2.isNotEmpty,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // 加载进度条
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: Center(
                child: Container(
                  width: 300,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _loadingMessage,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      LinearProgressIndicator(
                        value: _loadingProgress,
                        minHeight: 8,
                        backgroundColor: Colors.grey[200],
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(Colors.blue),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${(_loadingProgress * 100).toStringAsFixed(0)}%',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // 构建文档显示视图 - 使用RectGetter包装
  Widget _buildDocumentView({
    required String title,
    required List<TextElement> elements,
    required Set<int> highlightedSentences,
    required Map<int, GlobalKey<RectGetterState>> itemKeys,
    required GlobalKey<RectGetterState> listViewKey,
    required ScrollController scrollController,
    required Function(int) onTap,
    required VoidCallback onNextDuplicate,
    required bool hasDuplicates,
  }) {
    return Column(
      children: [
        // 标题栏和按钮
        Container(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: hasDuplicates ? onNextDuplicate : null,
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                child: const Text('下一个重复'),
              ),
            ],
          ),
        ),
        Expanded(
          child: RectGetter(
            key: listViewKey,
            child: Scrollbar(
              controller: scrollController,
              thumbVisibility: true,
              trackVisibility: true,
              thickness: 8,
              radius: const Radius.circular(4),
              child: ListView.builder(
                controller: scrollController,
                itemCount: elements.length,
                itemBuilder: (context, index) {
                  final element = elements[index];
                  bool isHighlighted = highlightedSentences.contains(index);
                  GlobalKey<RectGetterState>? itemKey = itemKeys[index];

                  // 修复：使用非空断言确保itemKey不为null
                  return RectGetter(
                    key: itemKey!,
                    child: GestureDetector(
                      onTap: element.isDuplicate ? () => onTap(index) : null,
                      child: Container(
                        color:
                            isHighlighted ? Colors.yellow : Colors.transparent,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 24,
                              alignment: Alignment.topCenter,
                              child: Text(
                                '${index + 1}.',
                                style: TextStyle(
                                  color: element.isDuplicate
                                      ? Colors.red
                                      : Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    element.text,
                                    style: TextStyle(
                                      color: element.isDuplicate
                                          ? Colors.red
                                          : Colors.black,
                                      fontSize: 16,
                                    ),
                                  ),
                                  if (element.isDuplicate)
                                    Container(
                                      margin: const EdgeInsets.only(top: 4),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        // ignore: deprecated_member_use
                                        color: Colors.blue.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '重复率: ${_getSentenceSimilarityText(index, elements == _elements1)}',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.blue,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 获取句子重复率文本
  String _getSentenceSimilarityText(int index, bool isFirstDocument) {
    final similarityMap =
        isFirstDocument ? _sentenceSimilarity1 : _sentenceSimilarity2;
    if (similarityMap.containsKey(index)) {
      return '${similarityMap[index]!.toStringAsFixed(1)}%';
    }
    return '计算中...';
  }
}

class TextElement {
  final String text;
  final bool isDuplicate;
  TextElement({required this.text, required this.isDuplicate});
}
