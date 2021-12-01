#!/bin/bash

partieFini=false		#boolean pour connaitre l'état de la partie
cartes=()			#tableau qui represente les cartes du jeu au départ
cartesManche=()			#tableau qui represente les cartes du jeu durant une manche
nbJoueurs=0			#nombre de joueurs
nbRobots=0			#nombre de robots
nbJoueursTotaux=0		#nombre de participant totaux
declare -i manche=0		#nombre de manche de la partie, declare en integer (afin dutiliser +=)
declare -i carteDistibue=0	#nombre de carte distribuer dans la partie
declare -i carteRestante=0	#nombre de carte restante dans une manche

initJoueurs()
{	
	#initialiser les joueurs
	echo Pour commencer, selectionner le nombre de joueur"("s")"  :
	read nbJoueurs
	
	if [ $nbJoueurs != 0 ];
	then
		for i in $(eval echo {1..$nbJoueurs});
		do	
			#ouvre un terminal pour chaque joueur
			gnome-terminal -e "bash -c './Joueurs.sh $i;$SHELL'"  #$i represente le numero du joueurs
		done
	fi
}

initRobots()
{
	#initialiser les robots
	echo Ensuite selectionner le nombre de robot"("s")" :
	read nbRobots
	
	if [ $nbRobots != 0 ];
	then
		for i in $(eval echo {1..$nbRobots});
		do
			num=$(($nbJoueurs + $i))
			#ouvre un terminal pour chaque robot mais tous est automatisé
			gnome-terminal -e "bash -c './Robots.sh $num;$SHELL'" 
		done
	fi
}

#methode qui remplie un tableau qui represente l'ensemble des cartes, de 1 a 100 au départ
remplieCartes()
{
	for i in {1..100};
	do	
		cartes+=($i)
		#echo ${cartes[$i-1]}
	done
}

#methode qui va distribuer les cartes du jeu au joueur(s) de la partie
distribueCartes()
{
	#on incremente le nombre de manche a chaque distribution de cartes au joueurs
	manche+=1 
	echo Manche : $manche
	for i in $(eval echo {1..$nbJoueursTotaux});
	do
		echo "" > tmp/cartePartie
		#manche permet de savoir combien de carte par participant il faut distribuer
		for j in $(eval echo {1..$manche}); 
		do
			if [ $carteDistibue -gt $((98)) ];
			then
				
				echo Trop de carte distribué, fin de la partie.
				exitPartie "Trop de carte distribué, fin de la partie."
			fi
				
			randomCarte=$(($RANDOM % $((99 - $carteDistibue)))) #indice d'une carte tiré au hasard
			
			#toutes les cartes de la manche courante
			cartesManche+=(${cartes[$randomCarte]})
			
			#stock les cartes au cout par cout dans un fichier temporaire
			echo ${cartes[$randomCarte]} >> tmp/cartePartie

			retireCarte $randomCarte

			carteDistibue+=1	
		done
		echo Cartes : $(cat tmp/cartePartie)
		echo "Cartes distribue" | nc -l -p 9091 
		echo on a passer la distribution
		sleep 1 #laisse le temps au participants de recuperer les cartes
	done
	
	carteRestante=$(($nbJoueursTotaux * $manche))
}

#methode qui retire la carte envoyer au joueur du tableau des cartes 
retireCarte()
{	
	carteRetirer=$1		 #indice de la carte a retirer 
	cartesTemp=()		 #tableau temporaire 
	
	#on vide le tableau de tout son contenue avant de le remplir
	unset cartesTemp 
	
	#on copie les cartes du joueur
	cartesTemp=("${cartes[@]}")
	
	#on vide le tableau de tout son contenue avant de le remplir
	unset cartes
	
	#recupere les bonnes valeurs 
	for i in $(eval echo {0..$((${#cartesTemp[*]} - 1))});
	do	
		if (( "$carteRetirer" != ${cartesTemp[$i]} ));
		then
			cartes+=(${cartesTemp[$i]})	
		fi
	done
}

#methode qui envoie le top depart de la partie
topDepart()
{
	for i in $(eval echo {1..$nbJoueursTotaux});
	do
		onAttend=true
		while [ $onAttend == "true" ]
		do
			echo "Vous avez recu le top depart." | nc localhost 9092 2> /dev/null & onAttend=false
		done
	done
}

#methode qui permet de traiter les informations recu par l'ensemble des joueurs
traitementManche()
{
	carteAJouer=100		#la carte la plus petite du paquet des cartes de la manche en cours
	carteCourante=0		#carte courante du joueur
	numParticipant=0	#numero du participant
	
	#on chercher la plus petite carte
	carteAParcourir=$(( ${#cartesManche[*]} - 1 ))
	
	for i in $(eval echo {0..$carteAParcourir});
	do	
		if (( "${cartesManche[$i]}" < "$carteAJouer" ));
		then
			carteAJouer=${cartesManche[$i]}
		fi
	done
	
	echo "Attente de connexion d'un joueur." | nc -l -p 9093 2> /dev/null 
	
	carteCourante=$(cat tmp/carteAJouer)
	echo "" > tmp/carteAJouer
	numParticipant=$(cat tmp/numJoueur)
	echo "" > tmp/numJoueur

	echo Carte courante : $carteCourante et carte a jouer : $carteAJouer
	if [ "$carteCourante" == "$carteAJouer" ];
	then
		#on enleve la carte des cartes de la manche
		cartesManche=( ${cartesManche[*]/$carteCourante} )	
		
		#envoyer ce message a tous les joueurs/robots
		echo "" > tmp/carteJouer
		echo "Carte $carteCourante joué par le participant n°$numParticipant" > tmp/carteJouer
		
		carteRestante=$((carteRestante - 1))
	else 	
		exitPartie "Mauvaise carte joué, fin de la partie. Carte $carteCourante du participant n°$numParticipant"
	fi
}

#methode qui permet de faire tourner la partie tant qu'elle n'est pas finie
deroulementPartie()
{
	while [ $partieFini == "false" ]
	do
		#traite les informations de la partie
		traitementManche 
		
		#si les joueurs non plus de cartes on en redistribue
		if (( "$carteRestante" == 0 ));
		then
			unset cartesManche
			echo Resdistribuer > tmp/redistribuer
 			distribueCartes
 			echo "" > tmp/redistribuer
 		fi;
	done
}

#methode qui permet quand la partie est finie d'écrire un top 10 des parties dans le gestionnaire du jeu
#ajoute également la partie courante terminé à l'ensemble du fichier
classementPartie()
{	
	#on met dans le fichier classement le nombre de manche et le nombre de joueur peut importe leurs nombre
	echo -e "$manche\t\t\t$nbJoueursTotaux" >> Classement.txt
	
	#on trie le fichier classement
	sort -n Classement.txt -o Classement.txt
	
	echo "Voici le classement dans l'ordre croissant des partie qui on durer le plus longtemps"
	head -n 1  Classement.txt	
	tail -n 10 Classement.txt
}

#fonction qui permet d'arreter la partie si une erreur a était detecte
exitPartie()
{
	echo "fin" > tmp/finGame
	echo $1 >> tmp/finGame
	classementPartie
	partieFini=true
}

#methode qui demarre la partie 
startPartie()
{
	remplieCartes
	
	initJoueurs
	initRobots
	
	nbJoueursTotaux=$(($nbJoueurs + $nbRobots))
	#echo Nous avons donc $nbJoueursTotaux participants pour cette partie
	
	echo "" > tmp/finGame
	echo "" > tmp/cartePartie
	echo "" > tmp/carteAJouer
	echo "" > tmp/numJoueur
	echo ""	> tmp/redistribuer
	
	#on distribue les cartes une premiere fois avant le top depart
	distribueCartes
	
	#envoie le top depart apres la distribution des cartes a tout les joueurs
	topDepart
	
	deroulementPartie
}

startPartie
