import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloudreve/entity/MFile.dart';
import 'package:cloudreve/utils/HttpUtil.dart';
import 'package:cloudreve/utils/Service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:open_file/open_file.dart';
import 'package:photo_view/photo_view.dart';

Map<String, String> _downloadUrlCache = {};
Map<String, Uint8List> _imageCache = {};
Map<String, Uint8List> _thumbCache = {};

enum Mode { list, grid }
typedef void ChangeDoubleCallBack(double newValue);
typedef void ChangeStringCallBack(String newValue);
typedef void RefreshCallBack(bool b);

class Home extends StatelessWidget {
  /// 上次返回时间
  int _lastBack = -1;

  ///默认下载路径
  String downPath = "/storage/emulated/0/Download/";

  /// 修改path函数
  ChangeStringCallBack changePath;

  /// 修改进度函数
  ChangeDoubleCallBack changeProgressNum;

  /// 文件排序比较函数
  int Function(MFile, MFile)? compare;

  /// 路径
  String path;

  /// 访问文件数据
  Future<Response> fileResp;

  /// 进度
  double progressNum = -1;

  /// 刷新函数
  RefreshCallBack refresh;

  /// 类型
  Mode mode;

  /// 外间距
  double paddingNum = 10;

  final imageRex = RegExp(r".*\.(jpg|gif|bmp|png|jpeg)");
  final pdfRex = RegExp(r".*\.(pdf)");
  final wordRegex = RegExp(r".*\.(doc|docx)");
  final zipRegex = RegExp(r".*\.(zip|rar|7z)");
  final apkRegex = RegExp(r".*\.(apk)");

  Home(
      {required this.changePath,
      required this.path,
      required this.progressNum,
      required this.changeProgressNum,
      required this.fileResp,
      required this.refresh,
      required this.mode,
      this.compare});

  @override
  Widget build(BuildContext context) {
    /// 进度条
    Widget _progressBar = Container(
      padding: EdgeInsets.symmetric(horizontal: paddingNum),
      child: Row(
        children: [
          Expanded(
            child: LinearProgressIndicator(
              value: progressNum,
              backgroundColor: Colors.grey,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
            ),
          ),
          Container(
            padding: EdgeInsets.only(left: 10),
            child: Text((progressNum * 100).toStringAsFixed(1) + "%"),
          ),
          // Container(
          //     padding: EdgeInsets.only(left: 10),
          //     child: TextButton(
          //       child: Text("Cancel"),
          //       onPressed: () {},
          //     ))
        ],
      ),
    );

    return WillPopScope(
      child: FutureBuilder(
        future: fileResp,
        builder: (BuildContext context, AsyncSnapshot<Response> snapshot) {
          if (snapshot.hasData) {
            var data = snapshot.data!.data['data'];
            var head = _buildHead(context);
            if (data != null) {
              var objects = data['objects'];

              var fileList = MFile.getFileList(objects, compare);

              List<Widget> widgetList = [];

              widgetList.add(head);
              widgetList.add(Divider(color: Colors.blue));

              if (progressNum != -1) {
                widgetList.insert(0, _progressBar);
              }
              switch (mode) {
                case Mode.list:
                  var item = Expanded(
                    child: Scrollbar(
                      child: RefreshIndicator(
                        onRefresh: () {
                          return _refresh(context);
                        },
                        child: ListView.builder(
                          itemBuilder: (context, index) {
                            return _buildListItem(context, fileList[index]);
                          },
                          itemCount: fileList.length,
                        ),
                      ),
                    ),
                  );
                  widgetList.add(item);
                  break;
                case Mode.grid:
                  var item = Expanded(
                    child: Scrollbar(
                      child: RefreshIndicator(
                        onRefresh: () {
                          return _refresh(context);
                        },
                        child: GridView.builder(
                          gridDelegate:
                              new SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2, //Grid按两列显示
                            mainAxisSpacing: paddingNum,
                            crossAxisSpacing: 5.0,
                          ),
                          itemBuilder: (context, index) {
                            return _buildGridItem(
                                context, fileList[index], index);
                          },
                          itemCount: fileList.length,
                        ),
                      ),
                    ),
                  );
                  widgetList.add(item);
                  break;
              }

              return Container(
                child: Column(
                  children: widgetList,
                ),
                padding: EdgeInsets.symmetric(horizontal: paddingNum),
              );
            } else {
              List<Widget> widgetList = <Widget>[
                head,
                Divider(color: Colors.blue),
                Center(child: Text("暂无数据"))
              ];

              if (progressNum != -1) {
                widgetList.insert(0, _progressBar);
              }

              return ListView.builder(
                itemCount: widgetList.length,
                itemBuilder: (context, index) {
                  return widgetList[index];
                },
              );
            }
          } else {
            return Center(child: Text("加载中"));
          }
        },
      ),
      onWillPop: () async {
        if (path == "/") {
          if (_lastBack == -1) {
            Fluttertoast.showToast(
                msg: "再次滑动返回",
                toastLength: Toast.LENGTH_SHORT,
                gravity: ToastGravity.CENTER,
                timeInSecForIosWeb: 1,
                backgroundColor: Colors.red,
                textColor: Colors.white,
                fontSize: 16.0);
            _lastBack = DateTime.now().microsecondsSinceEpoch;
            return false;
          } else {
            int now = DateTime.now().millisecondsSinceEpoch;
            if (now - _lastBack >= 1000) {
              _lastBack = now;
              return false;
            } else {
              return true;
            }
          }
        } else {
          List<String> paths1 = path.split("/");
          paths1[0] = "/";
          var paths2 = paths1.where((e) {
            return e != "";
          }).toList();
          String before = "/";
          for (int i = 1; i < paths2.length - 1; i++) {
            before += paths2[i];
          }
          changePath(before);
          refresh(true);
          return false;
        }
      },
    );
  }

  /// 构建网格项
  Widget _buildGridItem(BuildContext context, MFile file, int index) {
    Icon icon = Icon(Icons.file_present);
    bool isImage = false;

    if (file.type == "dir") {
      icon = Icon(Icons.folder, color: Colors.grey);
    } else {
      if (imageRex.hasMatch(file.name)) {
        icon = Icon(Icons.image, color: Colors.grey);
        isImage = true;
      } else if (pdfRex.hasMatch(file.name)) {
        icon = Icon(
          Icons.picture_as_pdf,
          color: Colors.red,
        );
      } else if (zipRegex.hasMatch(file.name)) {
        icon = Icon(Icons.archive, color: Colors.grey);
      } else if (wordRegex.hasMatch(file.name)) {
        icon = Icon(Icons.book, color: Colors.grey);
      } else if (apkRegex.hasMatch(file.name)) {
        icon = Icon(
          Icons.android,
          color: Colors.green,
        );
      }
    }

    double maxHeight = MediaQuery.of(context).size.width;
    double size = (maxHeight - paddingNum * 3) ~/ 2 - 62;
    Widget headImage;
    if (!isImage) {
      headImage = Container(height: size, child: icon);
    } else {
      headImage = FutureBuilder(
        future: _geThumbImage(file.id),
        builder: (BuildContext context, AsyncSnapshot<Response> snapshot) {
          if (snapshot.hasData) {
            if (_thumbCache[file.id] == null) {
              _thumbCache[file.id] = snapshot.data!.data as Uint8List;
            }
            return Container(
              child: ConstrainedBox(
                child: Image.memory(
                  snapshot.data!.data,
                  fit: BoxFit.cover,
                ),
                constraints: BoxConstraints.expand(),
              ),
              height: size,
            );
          } else {
            return Container(
              child: SizedBox(
                child: CircularProgressIndicator(),
                height: 44.0,
                width: 44.0,
              ),
              alignment: Alignment.center,
              height: size,
              width: size,
            );
          }
        },
      );
    }

    return InkWell(
      child: Card(
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            headImage,
            Divider(
              color: Colors.grey,
              height: 0,
            ),
            ListTile(
              leading: icon,
              title: Text(
                file.name,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      onTap: () {
        if (file.type == "file") {
          if (imageRex.hasMatch(file.name)) {
            _imageTap(context, file);
          } else {
            _openFileButtonTap(context, null, file);
          }
        } else {
          _dirTap(file);
        }
      },
      onDoubleTap: () {},
      onLongPress: () {
        if (file.type == "file") {
          _fileLongPress(context, file);
        } else {
          _dirLongPress(context, file);
        }
      },
    );
  }

  /// 构建头部
  Widget _buildHead(BuildContext context) {
    List<String> paths1 = path.split("/");
    List<Widget> buttons = <Widget>[];
    paths1[0] = "/";

    var paths2 = paths1.where((e) {
      return e != "";
    }).toList();

    for (int i = 0; i < paths2.length; i++) {
      var button = ElevatedButton(
        onPressed: () {
          if (i == 0) {
            changePath("/");
          } else {
            String before = "/";
            for (int j = 1; j <= i; j++) {
              if (j == i) {
                before += paths2[j];
              } else {
                before += paths2[j] + "/";
              }
            }
            changePath(before);
          }
          refresh(true);
        },
        child: Text(paths2[i]),
      );
      buttons.add(button);
    }

    return ButtonBar(
      alignment: MainAxisAlignment.start,
      children: buttons,
    );
  }

  /// 构建文件列表浏览
  Widget _buildListItem(BuildContext context, MFile file) {
    Icon icon = Icon(Icons.file_present);

    if (file.type == "dir") {
      icon = Icon(Icons.folder);
    } else {
      if (imageRex.hasMatch(file.name)) {
        icon = Icon(Icons.image);
      } else if (pdfRex.hasMatch(file.name)) {
        icon = Icon(
          Icons.picture_as_pdf,
          color: Colors.red,
        );
      } else if (zipRegex.hasMatch(file.name)) {
        icon = Icon(Icons.archive);
      } else if (wordRegex.hasMatch(file.name)) {
        icon = Icon(Icons.book);
      } else if (apkRegex.hasMatch(file.name)) {
        icon = Icon(
          Icons.android,
          color: Colors.green,
        );
      }
    }

    return InkWell(
      child: Card(
        child: ListTile(
          leading: icon,
          title: Text(file.name),
        ),
      ),
      onTap: () {
        if (file.type == "file") {
          if (imageRex.hasMatch(file.name)) {
            _imageTap(context, file);
          } else {
            _openFileButtonTap(context, null, file);
          }
        } else {
          _dirTap(file);
        }
      },
      onDoubleTap: () {},
      onLongPress: () {
        if (file.type == "file") {
          _fileLongPress(context, file);
        } else {
          _dirLongPress(context, file);
        }
      },
    );
  }

  /// 目录单击事件
  void _dirTap(file) {
    if (path == "/") {
      changePath(path + file.name);
    } else {
      changePath(path + "/" + file.name);
    }
    refresh(true);
  }

  /// 目录长按事件
  void _dirLongPress(BuildContext context, MFile file) {
    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          actions: <Widget>[
            TextButton(
              child: Text("删除"),
              onPressed: () async {
                Response delRes = await Service.deleteItem([file.id], []);
                if (delRes.data['code'] == 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("删除成功"),
                    ),
                  );
                  Navigator.pop(_);
                  changePath(path);
                  refresh(true);
                }
              },
            ),
          ],
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text("文件夹名:\t\t${file.name}"),
              Text("上传时间:\t\t${file.getFormatDate()}")
            ],
          ),
        );
      },
    );
  }

  /// 文件长按事件
  void _fileLongPress(BuildContext context, MFile file) {
    showDialog(
      context: context,
      builder: (dirtyContext) {
        return AlertDialog(
          actions: <Widget>[
            TextButton(
              child: Text("删除"),
              onPressed: () async {
                Response delRes = await Service.deleteItem([], [file.id]);
                if (delRes.data['code'] == 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("删除成功"),
                    ),
                  );
                  Navigator.pop(dirtyContext);
                  changePath(path);
                  refresh(true);
                }
              },
            ),
            TextButton(
              child: const Text('打开'),
              onPressed: () async {
                _openFileButtonTap(context, dirtyContext, file);
              },
            ),
            TextButton(
              child: const Text('下载'),
              onPressed: () async {
                _downloadButtonTap(context, dirtyContext, file);
              },
            ),
          ],
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text("文件名:\t\t${file.name}"),
              Text("文件大小:\t\t${MFile.getFileSize(file.size.toDouble(), 1)}"),
              Text("上传时间:\t\t${file.getFormatDate()}")
            ],
          ),
        );
      },
    );
  }

  /// 获取缩略图
  Future<Response> _geThumbImage(String fileId) async {
    if (_thumbCache[fileId] == null) {
      return Service.getThumb(fileId);
    } else {
      Response response = Response(requestOptions: RequestOptions(path: ""));
      response.data = _thumbCache[fileId];
      return response;
    }
  }

  /// 获取图像
  Future<Response> _getImage(MFile file) async {
    if (_imageCache[file.id] == null) {
      String downloadUrl;
      if (_downloadUrlCache[file.id] == null) {
        Response getUrlResp = await Service.getDownloadUrl(file.id);
        downloadUrl = getUrlResp.data['data'].toString();
        _downloadUrlCache[file.id] = downloadUrl;
      } else {
        downloadUrl = _downloadUrlCache[file.id]!;
      }
      return HttpUtil.dio
          .get(downloadUrl, options: Options(responseType: ResponseType.bytes));
    } else {
      Response response = Response(requestOptions: RequestOptions(path: ""));
      response.data = _imageCache[file.id];
      return response;
    }
  }

  /// 图片点击事件
  void _imageTap(BuildContext context, MFile file) {
    var image = FutureBuilder(
      future: _getImage(file),
      builder: (BuildContext context, AsyncSnapshot<Response> snapshot) {
        if (snapshot.hasData) {
          if (_imageCache[file.id] == null) {
            _imageCache[file.id] = snapshot.data!.data as Uint8List;
          }
          return Container(
            child: PhotoView(
              imageProvider: Image.memory(
                snapshot.data!.data,
                fit: BoxFit.contain,
              ).image,
            ),
          );
        } else {
          return Container(
            child: SizedBox(
              child: CircularProgressIndicator(),
              height: 44.0,
              width: 44.0,
            ),
            alignment: Alignment.center,
          );
        }
      },
    );

    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          contentPadding: EdgeInsets.zero,
          insetPadding: EdgeInsets.zero,
          backgroundColor: Colors.black26,
          content: Container(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            child: ConstrainedBox(
              child: image,
              constraints: BoxConstraints.expand(),
            ),
          ),
        );
      },
    );
  }

  /// 刷新函数
  Future<Null> _refresh(BuildContext context) {
    return Future.delayed(
      Duration(seconds: 1),
      () {
        // 延迟1s完成刷新
        refresh(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("刷新完成"),
          ),
        );
      },
    );
  }

  /// 下载按钮点击
  void _downloadButtonTap(
      BuildContext context, BuildContext? dialogContext, MFile file) async {
    File f = File(downPath + file.name);
    var exist = await f.exists();
    if (exist) {
      if (dialogContext != null) {
        Navigator.pop(dialogContext);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("文件已存在"),
        ),
      );
    } else {
      Response response = await Service.getDownloadUrl(file.id);
      String url = response.data['data'].toString();
      Dio dio = Dio();
      try {
        if (dialogContext != null) {
          Navigator.pop(dialogContext);
        }
        response = await dio.download(url, downPath + file.name,
            onReceiveProgress: (process, total) {
          changeProgressNum(process / total);
        });
        if (response.statusCode == 200) {
          String snackString = '下载至:' + downPath + file.name;
          changeProgressNum(-1);
          refresh(true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(snackString),
            ),
          );
        } else {
          throw Exception('接口出错');
        }
      } catch (e) {
        return print(e);
      }
    }
  }

  /// 打开按钮点击
  void _openFileButtonTap(
      BuildContext context, BuildContext? dialogContext, MFile file) async {
    if (imageRex.hasMatch(file.name)) {
      _imageTap(context, file);
    } else {
      File f = File(downPath + file.name);
      var exist = await f.exists();
      if (exist) {
        if (dialogContext != null) {
          Navigator.pop(dialogContext);
        }
        final _result = await OpenFile.open(downPath + file.name);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_result.message),
          ),
        );
      } else {
        Response response = await Service.getDownloadUrl(file.id);
        String url = response.data['data'].toString();
        Dio dio = Dio();
        try {
          if (dialogContext != null) {
            Navigator.pop(dialogContext);
          }
          response = await dio.download(url, downPath + file.name,
              onReceiveProgress: (process, total) {});
          if (response.statusCode == 200) {
            refresh(true);
            final _result = await OpenFile.open(downPath + file.name);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(_result.message),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("打开失败"),
              ),
            );
          }
        } catch (e) {
          return print(e);
        }
      }
    }
  }
}
