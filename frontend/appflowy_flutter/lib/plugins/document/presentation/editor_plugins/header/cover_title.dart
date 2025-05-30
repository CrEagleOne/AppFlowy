import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/application/document_appearance_cubit.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/shared_context/shared_context.dart';
import 'package:appflowy/shared/text_field/text_filed_with_metric_lines.dart';
import 'package:appflowy/workspace/application/appearance_defaults.dart';
import 'package:appflowy/workspace/application/view/view_bloc.dart';
import 'package:appflowy/workspace/application/view_info/view_info_bloc.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:universal_platform/universal_platform.dart';

class CoverTitle extends StatelessWidget {
  const CoverTitle({
    super.key,
    required this.view,
  });

  final ViewPB view;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ViewBloc(view: view)..add(const ViewEvent.initial()),
      child: _InnerCoverTitle(
        view: view,
      ),
    );
  }
}

class _InnerCoverTitle extends StatefulWidget {
  const _InnerCoverTitle({
    required this.view,
  });

  final ViewPB view;

  @override
  State<_InnerCoverTitle> createState() => _InnerCoverTitleState();
}

class _InnerCoverTitleState extends State<_InnerCoverTitle> {
  final titleTextController = TextEditingController();

  late final editorContext = context.read<SharedEditorContext>();
  late final editorState = context.read<EditorState>();
  late final titleFocusNode = editorContext.coverTitleFocusNode;
  int lineCount = 1;

  bool updatingViewName = false;

  @override
  void initState() {
    super.initState();

    titleTextController.text = widget.view.name;
    titleTextController.addListener(_onViewNameChanged);

    titleFocusNode
      ..onKeyEvent = _onKeyEvent
      ..addListener(_onFocusChanged);

    editorState.selectionNotifier.addListener(_onSelectionChanged);

    _requestInitialFocus();
  }

  @override
  void dispose() {
    titleFocusNode
      ..onKeyEvent = null
      ..removeListener(_onFocusChanged);
    titleTextController.dispose();
    editorState.selectionNotifier.removeListener(_onSelectionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fontStyle = Theme.of(context)
        .textTheme
        .bodyMedium!
        .copyWith(fontSize: 40.0, fontWeight: FontWeight.w700);
    final width = context.read<DocumentAppearanceCubit>().state.width;
    return BlocConsumer<ViewBloc, ViewState>(
      listenWhen: (previous, current) =>
          previous.view.name != current.view.name && !updatingViewName,
      listener: _onListen,
      builder: (context, state) {
        final appearance = context.read<DocumentAppearanceCubit>().state;
        return Container(
          constraints: BoxConstraints(maxWidth: width),
          child: Theme(
            data: Theme.of(context).copyWith(
              textSelectionTheme: TextSelectionThemeData(
                cursorColor: appearance.selectionColor,
                selectionColor: appearance.selectionColor ??
                    DefaultAppearanceSettings.getDefaultSelectionColor(context),
              ),
            ),
            child: TextFieldWithMetricLines(
              controller: titleTextController,
              enabled: editorState.editable,
              focusNode: titleFocusNode,
              style: fontStyle,
              onLineCountChange: (count) => lineCount = count,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: LocaleKeys.menuAppHeader_defaultNewPageName.tr(),
                hintStyle: fontStyle.copyWith(
                  color: Theme.of(context).hintColor,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _requestInitialFocus() {
    if (editorContext.requestCoverTitleFocus) {
      void requestFocus() {
        titleFocusNode.canRequestFocus = true;
        titleFocusNode.requestFocus();
        editorContext.requestCoverTitleFocus = false;
      }

      // on macOS, if we gain focus immediately, the focus won't work.
      // It's a workaround to delay the focus request.
      if (UniversalPlatform.isMacOS) {
        Future.delayed(Durations.short4, () {
          requestFocus();
        });
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          requestFocus();
        });
      }
    }
  }

  void _onSelectionChanged() {
    // if title is focused and the selection is not null, clear the selection
    if (editorState.selection != null && titleFocusNode.hasFocus) {
      Log.info('title is focused, clear the editor selection');
      editorState.selection = null;
    }
  }

  void _onListen(BuildContext context, ViewState state) {
    _requestFocusIfNeeded(widget.view, state);

    if (state.view.name != titleTextController.text) {
      titleTextController.text = state.view.name;
    }
  }

  bool _shouldFocus(ViewPB view, ViewState? state) {
    final name = state?.view.name ?? view.name;

    if (editorState.document.root.children.isNotEmpty) {
      return false;
    }

    // if the view's name is empty, focus on the title
    if (name.isEmpty) {
      return true;
    }

    return false;
  }

  void _requestFocusIfNeeded(ViewPB view, ViewState? state) {
    final shouldFocus = _shouldFocus(view, state);
    if (shouldFocus) {
      titleFocusNode.requestFocus();
    }
  }

  void _onFocusChanged() {
    if (titleFocusNode.hasFocus) {
      // if the document is empty, disable the keyboard service
      final children = editorState.document.root.children;
      final firstDelta = children.firstOrNull?.delta;
      final isEmptyDocument =
          children.length == 1 && (firstDelta == null || firstDelta.isEmpty);
      if (!isEmptyDocument) {
        return;
      }

      if (editorState.selection != null) {
        Log.info('cover title got focus, clear the editor selection');
        editorState.selection = null;
      }

      Log.info('cover title got focus, disable keyboard service');
      editorState.service.keyboardService?.disable();
    } else {
      Log.info('cover title lost focus, enable keyboard service');
      editorState.service.keyboardService?.enable();
    }
  }

  void _onViewNameChanged() {
    updatingViewName = true;

    Debounce.debounce(
      'update view name',
      const Duration(milliseconds: 250),
      () {
        if (!mounted) {
          return;
        }
        if (context.read<ViewBloc>().state.view.name !=
            titleTextController.text) {
          context
              .read<ViewBloc>()
              .add(ViewEvent.rename(titleTextController.text));
        }
        context
            .read<ViewInfoBloc?>()
            ?.add(ViewInfoEvent.titleChanged(titleTextController.text));

        updatingViewName = false;
      },
    );
  }

  KeyEventResult _onKeyEvent(FocusNode focusNode, KeyEvent event) {
    if (event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      // if enter is pressed, jump the first line of editor.
      _createNewLine();
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      return _moveCursorToNextLine(event.logicalKey);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      return _moveCursorToNextLine(event.logicalKey);
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      return _exitEditing();
    } else if (event.logicalKey == LogicalKeyboardKey.tab) {
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  KeyEventResult _exitEditing() {
    titleFocusNode.unfocus();
    return KeyEventResult.handled;
  }

  Future<void> _createNewLine() async {
    titleFocusNode.unfocus();

    final selection = titleTextController.selection;
    final text = titleTextController.text;
    // split the text into two lines based on the cursor position
    final parts = [
      text.substring(0, selection.baseOffset),
      text.substring(selection.baseOffset),
    ];
    titleTextController.text = parts[0];

    final transaction = editorState.transaction;
    transaction.insertNode([0], paragraphNode(text: parts[1]));
    await editorState.apply(transaction);

    // update selection instead of using afterSelection in transaction,
    //  because it will cause the cursor to jump
    await editorState.updateSelectionWithReason(
      Selection.collapsed(Position(path: [0])),
      // trigger the keyboard service.
      reason: SelectionUpdateReason.uiEvent,
    );
  }

  KeyEventResult _moveCursorToNextLine(LogicalKeyboardKey key) {
    final selection = titleTextController.selection;
    final text = titleTextController.text;

    // if the cursor is not at the end of the text, ignore the event
    if ((key == LogicalKeyboardKey.arrowRight || lineCount != 1) &&
        (!selection.isCollapsed || text.length != selection.extentOffset)) {
      return KeyEventResult.ignored;
    }

    final node = editorState.getNodeAtPath([0]);
    if (node == null) {
      _createNewLine();
      return KeyEventResult.handled;
    }

    titleFocusNode.unfocus();

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      // delay the update selection to wait for the title to unfocus
      int offset = 0;
      if (key == LogicalKeyboardKey.arrowDown) {
        offset = node.delta?.length ?? 0;
      } else if (key == LogicalKeyboardKey.arrowRight) {
        offset = 0;
      }
      editorState.updateSelectionWithReason(
        Selection.collapsed(
          Position(path: [0], offset: offset),
        ),
        // trigger the keyboard service.
        reason: SelectionUpdateReason.uiEvent,
      );
    });

    return KeyEventResult.handled;
  }
}
