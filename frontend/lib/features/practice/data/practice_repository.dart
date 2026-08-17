import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../trading/data/local_account_store.dart';
import '../domain/practice_models.dart';

final practiceRepositoryProvider = Provider((ref) => PracticeRepository(LocalAccountStore()));

class PracticeRepository {
  PracticeRepository(this._store); final LocalAccountStore _store;
  List<TradeJournalEntry> journals() => _store.journals.map(TradeJournalEntry.fromJson).toList();
  List<TradingSetup> setups() => _store.setups.map(TradingSetup.fromJson).toList();
  RiskSettings riskSettings() { final raw=_store.riskSettings; return raw == null ? const RiskSettings() : RiskSettings.fromJson(raw); }
  Future<void> saveJournal(TradeJournalEntry entry) async { final all=_store.journals; final i=all.indexWhere((x)=>x['id']==entry.id); if(i<0){all.insert(0,entry.toJson());}else{all[i]=entry.toJson();} await _store.saveJournals(all); }
  Future<void> deleteJournal(String id) => _store.saveJournals(_store.journals.where((x)=>x['id']!=id).toList());
  Future<void> saveSetup(TradingSetup setup) async { final all=_store.setups; final i=all.indexWhere((x)=>x['id']==setup.id); if(i<0){all.insert(0,setup.toJson());}else{all[i]=setup.toJson();} await _store.saveSetups(all); }
  Future<void> saveRisk(RiskSettings settings) => _store.saveRiskSettings(settings.toJson());
}
