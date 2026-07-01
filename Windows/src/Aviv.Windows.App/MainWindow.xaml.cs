using System.ComponentModel;
using Aviv.Windows.App.Services;
using Aviv.Windows.App.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Input;
using Windows.System;

namespace Aviv.Windows.App;

public sealed partial class MainWindow : Window
{
    private readonly EditorDocumentViewModel viewModel;
    private bool syncingFromViewModel;

    public MainWindow()
    {
        InitializeComponent();

        viewModel = new EditorDocumentViewModel(new MarkdownFileService(this));
        RootGrid.DataContext = viewModel;
        EditorView.LoadMarkdown(viewModel.Markdown);

        viewModel.PropertyChanged += OnViewModelPropertyChanged;
        viewModel.EditRequested += action => EditorView.ApplyEditAction(action);
        viewModel.EditorCommandRequested += command => EditorView.PerformEditorCommand(command);
        viewModel.ViewScaleChanged += scale => EditorView.SetViewScale(scale);
        InstallKeyboardAccelerators();
        EditorView.MarkdownChanged += markdown =>
        {
            if (syncingFromViewModel)
            {
                return;
            }

            viewModel.UpdateFromEditor(markdown);
        };
    }

    private void OnViewModelPropertyChanged(object? sender, PropertyChangedEventArgs args)
    {
        if (args.PropertyName != nameof(EditorDocumentViewModel.Markdown) || EditorView.Markdown == viewModel.Markdown)
        {
            return;
        }

        syncingFromViewModel = true;
        EditorView.LoadMarkdown(viewModel.Markdown);
        syncingFromViewModel = false;
    }

    private void InstallKeyboardAccelerators()
    {
        AddAccelerator(VirtualKey.N, VirtualKeyModifiers.Control, () => viewModel.NewDocumentCommand.Execute(null));
        AddAccelerator(VirtualKey.T, VirtualKeyModifiers.Control, () => viewModel.NewTabCommand.Execute(null));
        AddAccelerator(VirtualKey.O, VirtualKeyModifiers.Control, () => viewModel.OpenDocumentCommand.Execute(null));
        AddAccelerator(VirtualKey.W, VirtualKeyModifiers.Control, () => viewModel.CloseDocumentCommand.Execute(null));
        AddAccelerator(VirtualKey.S, VirtualKeyModifiers.Control, () => viewModel.SaveDocumentCommand.Execute(null));
        AddAccelerator(VirtualKey.S, VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift, () => viewModel.SaveDocumentAsCommand.Execute(null));
        AddAccelerator(VirtualKey.P, VirtualKeyModifiers.Control, () => viewModel.PrintDocumentCommand.Execute(null));
        AddAccelerator(VirtualKey.Number0, VirtualKeyModifiers.Control, () => viewModel.ResetTextSizeCommand.Execute(null));
        AddAccelerator(VirtualKey.Add, VirtualKeyModifiers.Control, () => viewModel.IncreaseTextSizeCommand.Execute(null));
        AddAccelerator(VirtualKey.Subtract, VirtualKeyModifiers.Control, () => viewModel.DecreaseTextSizeCommand.Execute(null));
        AddAccelerator(VirtualKey.B, VirtualKeyModifiers.Control, () => viewModel.ToggleBoldCommand.Execute(null));
        AddAccelerator(VirtualKey.I, VirtualKeyModifiers.Control, () => viewModel.ToggleItalicCommand.Execute(null));
        AddAccelerator(VirtualKey.Oem3, VirtualKeyModifiers.Control, () => viewModel.ToggleCodeCommand.Execute(null));
        AddAccelerator(VirtualKey.Number1, VirtualKeyModifiers.Control, () => viewModel.Heading1Command.Execute(null));
        AddAccelerator(VirtualKey.Number2, VirtualKeyModifiers.Control, () => viewModel.Heading2Command.Execute(null));
        AddAccelerator(VirtualKey.Tab, VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift, () => viewModel.ShowPreviousTabCommand.Execute(null));
        AddAccelerator(VirtualKey.Tab, VirtualKeyModifiers.Control, () => viewModel.ShowNextTabCommand.Execute(null));
        AddAccelerator(VirtualKey.Z, VirtualKeyModifiers.Control, () => viewModel.UndoCommand.Execute(null));
        AddAccelerator(VirtualKey.Z, VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift, () => viewModel.RedoCommand.Execute(null));
        AddAccelerator(VirtualKey.X, VirtualKeyModifiers.Control, () => viewModel.CutCommand.Execute(null));
        AddAccelerator(VirtualKey.C, VirtualKeyModifiers.Control, () => viewModel.CopyCommand.Execute(null));
        AddAccelerator(VirtualKey.V, VirtualKeyModifiers.Control, () => viewModel.PasteCommand.Execute(null));
        AddAccelerator(VirtualKey.A, VirtualKeyModifiers.Control, () => viewModel.SelectAllCommand.Execute(null));
        AddAccelerator(VirtualKey.F, VirtualKeyModifiers.Control, () => viewModel.FindCommand.Execute(null));
        AddAccelerator(VirtualKey.F, VirtualKeyModifiers.Control | VirtualKeyModifiers.Menu, () => viewModel.FindAndReplaceCommand.Execute(null));
        AddAccelerator(VirtualKey.G, VirtualKeyModifiers.Control, () => viewModel.FindNextCommand.Execute(null));
        AddAccelerator(VirtualKey.G, VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift, () => viewModel.FindPreviousCommand.Execute(null));
    }

    private void AddAccelerator(VirtualKey key, VirtualKeyModifiers modifiers, Action action)
    {
        var accelerator = new KeyboardAccelerator
        {
            Key = key,
            Modifiers = modifiers
        };
        accelerator.Invoked += (_, args) =>
        {
            action();
            args.Handled = true;
        };
        RootGrid.KeyboardAccelerators.Add(accelerator);
    }
}
